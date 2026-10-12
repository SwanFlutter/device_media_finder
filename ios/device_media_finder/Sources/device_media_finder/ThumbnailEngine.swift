import Foundation
import Photos
import AVFoundation
import CryptoKit
import UIKit

/// The iOS equivalent of Android's `ThumbnailEngine`.
///
/// Generates a JPEG thumbnail and caches it on disk (LRU, 128 MB cap, MD5 key
/// of `source|w|h|stamp`), returning the file path. Identical requests already
/// in flight are de-duplicated, and generation is bounded by a semaphore so a
/// fast scroll cannot spawn hundreds of decodes at once — mirroring the Android
/// backend's behaviour.
///
/// The `source` is normally a `PHAsset.localIdentifier` (from
/// `PhotoLibraryScanner`); a `file://`/absolute path is also accepted for
/// assets a caller obtained through a document picker.
final class ThumbnailEngine {

    private static let maxConcurrent = 4
    private static let quality: CGFloat = 0.85
    private static let maxCacheBytes: UInt64 = 128 * 1024 * 1024

    private let dir: URL
    private let gate = DispatchSemaphore(value: ThumbnailEngine.maxConcurrent)
    private let lock = NSLock()
    private var inFlight: [String: DispatchSemaphore] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("mm_thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // ─── Public entry point ────────────────────────────────────────────────

    /// Blocking thumbnail resolver. Callers run on a background queue.
    func thumbnail(source: String, width: Int, height: Int,
                   stamp: Int64, kind: String) -> String? {
        let key = md5("\(source)|\(width)|\(height)|\(stamp)")
        let out = dir.appendingPathComponent("\(key).jpg")
        if let size = fileSize(out), size > 0 { return out.path }

        // De-duplicate concurrent identical requests: the first thread does the
        // work, the rest wait on a per-key semaphore then read the cache file.
        lock.lock()
        if let waiter = inFlight[key] {
            lock.unlock()
            waiter.wait()
            waiter.signal()
            return (fileSize(out) ?? 0) > 0 ? out.path : nil
        }
        let waiter = DispatchSemaphore(value: 0)
        inFlight[key] = waiter
        lock.unlock()

        gate.wait()
        defer {
            gate.signal()
            lock.lock()
            inFlight.removeValue(forKey: key)
            lock.unlock()
            waiter.signal()
        }

        guard let image = render(source: source, width: width, height: height, kind: kind) else {
            return nil
        }
        return save(image, to: out)
    }

    func clear() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    // ─── Rendering strategies ────────────────────────────────────────────────

    private func render(source: String, width: Int, height: Int, kind: String) -> UIImage? {
        let target = CGSize(width: width, height: height)
        // A Photos asset id never contains a path separator; anything with a
        // "/" (or a file URL) is treated as an on-disk file instead.
        if !source.contains("/") && !source.hasPrefix("file:") {
            return assetImage(localId: source, target: target)
        }
        let path = source.hasPrefix("file://")
            ? (URL(string: source)?.path ?? source)
            : source
        switch kind {
        case "video": return videoFrame(path: path, target: target)
        case "audio": return albumArt(path: path, target: target)
        default:       return imageThumb(path: path, target: target)
        }
    }

    private func assetImage(localId: String, target: CGSize) -> UIImage? {
        let res = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
        guard let asset = res.firstObject else { return nil }
        let opts = PHImageRequestOptions()
        opts.isSynchronous = true                    // safe: we're on a bg queue
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .exact
        opts.isNetworkAccessAllowed = true           // fetch iCloud originals
        var result: UIImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: target, contentMode: .aspectFill, options: opts
        ) { image, _ in result = image }
        return result
    }

    private func imageThumb(path: String, target: CGSize) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
        else { return nil }
        let maxPixel = Int(max(target.width, target.height))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    private func videoFrame(path: String, target: CGSize) -> UIImage? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = target
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func albumArt(path: String, target: CGSize) -> UIImage? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        for item in asset.commonMetadata where item.commonKey == .commonKeyArtwork {
            if let data = item.dataValue, let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    // ─── Saving + cache management ───────────────────────────────────────────

    private func save(_ image: UIImage, to out: URL) -> String? {
        guard let data = image.jpegData(compressionQuality: Self.quality) else { return nil }
        do {
            try data.write(to: out, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: out)
            return nil
        }
        if (fileSize(out) ?? 0) == 0 {
            try? FileManager.default.removeItem(at: out)
            return nil
        }
        trimCache()
        return out.path
    }

    private func trimCache() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys) else { return }
        var total: UInt64 = 0
        var entries: [(url: URL, size: UInt64, date: Date)] = []
        for f in files {
            let v = try? f.resourceValues(forKeys: Set(keys))
            let size = UInt64(v?.fileSize ?? 0)
            total += size
            entries.append((f, size, v?.contentModificationDate ?? .distantPast))
        }
        if total <= Self.maxCacheBytes { return }
        entries.sort { $0.date < $1.date }              // oldest first (LRU)
        for e in entries {
            if total <= Self.maxCacheBytes { break }
            try? FileManager.default.removeItem(at: e.url)
            total -= e.size
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────────

    private func fileSize(_ url: URL) -> UInt64? {
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let s = v.fileSize else { return nil }
        return UInt64(s)
    }

    private func md5(_ input: String) -> String {
        Insecure.MD5.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
