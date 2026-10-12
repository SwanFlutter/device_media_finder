import Foundation

/// The macOS equivalent of Android's `MediaStoreScanner`.
///
/// Unlike iOS, a macOS app can read the user's file system, so this scanner
/// mirrors the Android model directly: it walks the standard user media
/// directories, filters by media type (and optional extension list), and
/// returns rows of the same shape the Android `MediaStore` query produces —
/// covering images, video, audio, documents and archives of any size/format.
///
/// The walk is bounded exactly like the Android file-system fallback: depth ≤
/// `maxDepth`, a wall-clock budget, and a hard cap on the number of files, so a
/// pathological tree can never hang the scan.
final class FileSystemScanner {

    // MediaStore-compatible media-type codes (kept identical to Android).
    private static let TYPE_IMAGE = 1
    private static let TYPE_AUDIO = 2
    private static let TYPE_VIDEO = 3
    private static let TYPE_DOCUMENT = 6

    private static let maxDepth = 6
    private static let budgetSeconds: TimeInterval = 8.0
    private static let hardCap = 20_000

    private static let imageExts: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif", "tiff", "tif"
    ]
    private static let videoExts: Set<String> = [
        "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "3gp",
        "mpeg", "mpg", "ts", "m2ts"
    ]
    private static let audioExts: Set<String> = [
        "mp3", "wav", "flac", "aac", "ogg", "m4a", "wma", "opus", "aiff", "alac"
    ]
    private static let documentExts: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf",
        "odt", "ods", "odp", "epub", "mobi", "csv", "md"
    ]
    private static let archiveExts: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "apk", "iso"
    ]

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
    }

    // ─── Public API ──────────────────────────────────────────────────────────

    func queryPage(type: ScanType, extensions: [String],
                   offset: Int, limit: Int) -> [[String: Any]] {
        let all = scan(type: type, extensions: extensions)
        if offset >= all.count { return [] }
        return Array(all[offset..<min(offset + limit, all.count)]).map(row(for:))
    }

    func count(type: ScanType, extensions: [String]) -> Int {
        scan(type: type, extensions: extensions).count
    }

    // ─── Scanning ──────────────────────────────────────────────────────────

    private struct Entry {
        let url: URL
        let size: Int
        let modified: Date
        let ext: String
    }

    private func scan(type: ScanType, extensions: [String]) -> [Entry] {
        let explicit = normalized(extensions)
        let wanted = explicit.isEmpty ? extensionSet(for: type) : explicit
        let fm = FileManager.default
        let deadline = Date().addingTimeInterval(Self.budgetSeconds)

        var results: [Entry] = []
        var stack: [(url: URL, depth: Int)] = roots().map { ($0, 0) }

        while let node = stack.popLast() {
            if results.count >= Self.hardCap || Date() > deadline { break }
            guard let children = try? fm.contentsOfDirectory(
                at: node.url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                let values = try? child.resourceValues(
                    forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                if values?.isDirectory == true {
                    if node.depth + 1 <= Self.maxDepth && !isSkippableDir(child) {
                        stack.append((child, node.depth + 1))
                    }
                    continue
                }
                let ext = child.pathExtension.lowercased()
                // `wanted` empty means ANY-with-no-filter: accept every file.
                if !wanted.isEmpty && !wanted.contains(ext) { continue }
                results.append(Entry(
                    url: child,
                    size: values?.fileSize ?? 0,
                    modified: values?.contentModificationDate ?? Date(timeIntervalSince1970: 0),
                    ext: ext))
            }
        }
        // Newest first, matching the Android scanner's dateModified DESC order.
        results.sort { $0.modified > $1.modified }
        return results
    }

    private func roots() -> [URL] {
        let fm = FileManager.default
        let dirs: [FileManager.SearchPathDirectory] = [
            .moviesDirectory, .musicDirectory, .picturesDirectory,
            .downloadsDirectory, .documentDirectory, .desktopDirectory
        ]
        var urls: [URL] = []
        var seen = Set<String>()
        for d in dirs {
            if let u = fm.urls(for: d, in: .userDomainMask).first,
               fm.fileExists(atPath: u.path), seen.insert(u.path).inserted {
                urls.append(u)
            }
        }
        return urls
    }

    private func isSkippableDir(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return true }
        if name == "Library" || name == "node_modules" { return true }
        // Treat app/document bundles (.app, .photoslibrary, …) as opaque so we
        // don't descend into their internals.
        return isPackage(url)
    }

    private func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }

    // ─── Row mapping ──────────────────────────────────────────────────────────

    private func row(for e: Entry) -> [String: Any] {
        var row: [String: Any] = [
            "id": stableId(e.url.path),
            "uri": e.url.absoluteString,          // file:// URL
            "name": e.url.lastPathComponent,
            "size": e.size,
            "dateModified": Int(e.modified.timeIntervalSince1970 * 1000.0),
            "mediaType": mediaTypeCode(e.ext),
            "path": e.url.path,
            "width": 0,
            "height": 0,
            "duration": 0,
        ]
        if let mime = mimeFromExtension(e.ext) { row["mimeType"] = mime }
        return row
    }

    private func mediaTypeCode(_ ext: String) -> Int {
        if Self.imageExts.contains(ext) { return Self.TYPE_IMAGE }
        if Self.videoExts.contains(ext) { return Self.TYPE_VIDEO }
        if Self.audioExts.contains(ext) { return Self.TYPE_AUDIO }
        if Self.documentExts.contains(ext) { return Self.TYPE_DOCUMENT }
        return 0
    }

    private func extensionSet(for type: ScanType) -> Set<String> {
        switch type {
        case .image: return Self.imageExts
        case .video: return Self.videoExts
        case .audio: return Self.audioExts
        case .document: return Self.documentExts
        case .archive: return Self.archiveExts
        case .any: return []       // empty ⇒ accept every file
        }
    }

    private func mimeFromExtension(_ ext: String) -> String? {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "aac": return "audio/aac"
        case "ogg", "opus": return "audio/ogg"
        case "m4a": return "audio/mp4"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        default: return nil
        }
    }

    private func normalized(_ extensions: [String]) -> Set<String> {
        Set(extensions.map { ext -> String in
            let e = ext.lowercased()
            return e.hasPrefix(".") ? String(e.dropFirst()) : e
        }.filter { !$0.isEmpty })
    }

    private func stableId(_ path: String) -> Int {
        var hash: UInt64 = 1469598103934665603          // FNV-1a 64-bit
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash & 0x7FFF_FFFF_FFFF_FFFF)
    }
}
