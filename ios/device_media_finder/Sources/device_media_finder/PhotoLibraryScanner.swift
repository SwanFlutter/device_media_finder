import Foundation
import Photos

#if canImport(MobileCoreServices)
import MobileCoreServices
#endif
import UniformTypeIdentifiers

/// The iOS equivalent of Android's `MediaStoreScanner`.
///
/// iOS is sandboxed: an app cannot walk the file system looking for arbitrary
/// files the way Android can. The one system-indexed media catalogue an app may
/// read (with the user's permission) is the **Photos library**, which holds
/// images and videos. So this scanner maps:
///
///   * `image` / `video` / `any`  → `PHAsset` fetches (fully supported)
///   * `audio` / `document` / `archive` → empty (not reachable on iOS; audio
///     lives in the DRM-bound Music library, documents/archives only in
///     per-app sandboxes or the Files app via a user-driven picker).
///
/// Every field the Dart `MediaItem` expects is filled from `PHAsset` /
/// `PHAssetResource` metadata, so a player gets duration, resolution, size,
/// MIME type and a stable `uri` (the asset's `localIdentifier`) without a
/// second round-trip.
final class PhotoLibraryScanner {

    /// MediaStore-compatible media-type codes (kept identical to the Android
    /// backend so the shared Dart layer needs no per-platform branching).
    private static let TYPE_IMAGE = 1
    private static let TYPE_AUDIO = 2
    private static let TYPE_VIDEO = 3

    enum ScanType {
        case image, video, audio, document, archive, any

        static func parse(_ s: String?) -> ScanType {
            switch s {
            case "image": return .image
            case "video": return .video
            case "audio": return .audio
            case "document": return .document
            case "archive": return .archive
            default: return .any
            }
        }

        /// The `PHAsset` media types this scan covers, or `nil` when the type
        /// has no representation in the Photos library.
        var assetMediaTypes: [PHAssetMediaType]? {
            switch self {
            case .image: return [.image]
            case .video: return [.video]
            case .any:   return [.image, .video]
            case .audio, .document, .archive: return nil
            }
        }
    }

    // ─── Fetching ─────────────────────────────────────────────────────────

    /// Returns a page of rows sorted newest-first, matching the Android
    /// scanner's ordering (`dateModified DESC`).
    func queryPage(type: ScanType, extensions: [String],
                   offset: Int, limit: Int) -> [[String: Any]] {
        guard let fetch = fetchAssets(for: type) else { return [] }
        let exts = normalized(extensions)

        var rows: [[String: Any]] = []
        rows.reserveCapacity(min(limit, fetch.count))

        // Enumerate lazily and skip until `offset`, honouring the extension
        // filter, so paging stays O(offset+limit) rather than materialising
        // the whole library.
        var matched = 0
        var idx = 0
        while idx < fetch.count && rows.count < limit {
            let asset = fetch.object(at: idx)
            idx += 1
            if !exts.isEmpty {
                let ext = fileExtension(for: asset)
                if !exts.contains(ext) { continue }
            }
            if matched >= offset {
                rows.append(row(for: asset))
            }
            matched += 1
        }
        return rows
    }

    func count(type: ScanType, extensions: [String]) -> Int {
        guard let fetch = fetchAssets(for: type) else { return 0 }
        let exts = normalized(extensions)
        if exts.isEmpty { return fetch.count }
        var n = 0
        for i in 0..<fetch.count {
            if exts.contains(fileExtension(for: fetch.object(at: i))) { n += 1 }
        }
        return n
    }

    // ─── PHFetchResult construction ────────────────────────────────────────

    private func fetchAssets(for type: ScanType) -> PHFetchResult<PHAsset>? {
        guard let mediaTypes = type.assetMediaTypes else { return nil }
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "modificationDate", ascending: false),
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        let predicates = mediaTypes.map {
            NSPredicate(format: "mediaType == %d", $0.rawValue)
        }
        options.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        return PHAsset.fetchAssets(with: options)
    }

    // ─── Row mapping ────────────────────────────────────────────────────────

    private func row(for asset: PHAsset) -> [String: Any] {
        let resource = PHAssetResource.assetResources(for: asset).first
        let name = resource?.originalFilename
            ?? "\(asset.localIdentifier).\(defaultExtension(for: asset))"

        var size: Int = 0
        if let r = resource, let bytes = r.value(forKey: "fileSize") as? Int64 {
            size = Int(bytes)                       // Int is 64-bit on all iOS
        }

        let modified = asset.modificationDate ?? asset.creationDate ?? Date(timeIntervalSince1970: 0)
        let durationMs = asset.mediaType == .video ? Int(asset.duration * 1000.0) : 0

        var row: [String: Any] = [
            "id": stableId(asset.localIdentifier),
            "uri": asset.localIdentifier,           // resolved back in ThumbnailEngine
            "name": name,
            "size": size,
            "dateModified": Int(modified.timeIntervalSince1970 * 1000.0),
            "mediaType": mediaTypeCode(asset),
            "width": asset.pixelWidth,
            "height": asset.pixelHeight,
            "duration": durationMs,
        ]
        if let mime = mimeType(resource: resource, name: name) {
            row["mimeType"] = mime
        }
        // `path` is intentionally omitted: Photos assets are scoped, only the
        // `uri` (localIdentifier) is stable and resolvable.
        return row
    }

    private func mediaTypeCode(_ asset: PHAsset) -> Int {
        switch asset.mediaType {
        case .image: return Self.TYPE_IMAGE
        case .video: return Self.TYPE_VIDEO
        case .audio: return Self.TYPE_AUDIO
        default: return 0
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    private func fileExtension(for asset: PHAsset) -> String {
        let name = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
        return extLower(name).isEmpty ? defaultExtension(for: asset) : extLower(name)
    }

    private func defaultExtension(for asset: PHAsset) -> String {
        asset.mediaType == .video ? "mov" : "jpg"
    }

    private func mimeType(resource: PHAssetResource?, name: String) -> String? {
        if let uti = resource?.uniformTypeIdentifier {
            if #available(iOS 14.0, *) {
                if let mime = UTType(uti)?.preferredMIMEType { return mime }
            }
        }
        return mimeFromExtension(extLower(name))
    }

    private func mimeFromExtension(_ ext: String) -> String? {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "webp": return "image/webp"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return nil
        }
    }

    private func normalized(_ extensions: [String]) -> Set<String> {
        Set(extensions.map { ext in
            let e = ext.lowercased()
            return e.hasPrefix(".") ? String(e.dropFirst()) : e
        }.filter { !$0.isEmpty })
    }

    private func extLower(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.index(before: name.endIndex) else {
            return ""
        }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    /// A stable 63-bit id derived from the (String) `localIdentifier`, so the
    /// Dart `int id` field is populated and de-dupes correctly across pages.
    private func stableId(_ localIdentifier: String) -> Int {
        var hash: UInt64 = 1469598103934665603          // FNV-1a 64-bit
        for byte in localIdentifier.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash & 0x7FFF_FFFF_FFFF_FFFF)
    }
}
