import Flutter
import UIKit
import Photos

/// iOS backend for the `device_media_finder` plugin.
///
/// Mirrors the Android `MethodChannel` contract exactly (same method names,
/// argument keys and result shapes) so the shared Dart layer is unchanged. All
/// heavy work runs on a background queue; replies are always delivered on the
/// main thread, once.
///
/// Platform note: iOS is sandboxed, so `image`/`video` resolve against the
/// Photos library (the only user-media catalogue an app may read), while
/// `audio`/`document`/`archive` and arbitrary directory browsing have no iOS
/// equivalent and return empty. See `PhotoLibraryScanner` for details.
public class DeviceMediaFinderPlugin: NSObject, FlutterPlugin {

    private let scanner = PhotoLibraryScanner()
    private let thumbs = ThumbnailEngine()
    private let work = DispatchQueue(label: "device_media_finder.io",
                                     qos: .userInitiated, attributes: .concurrent)

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "device_media_finder", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(DeviceMediaFinderPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result rawResult: @escaping FlutterResult) {
        let result = SafeResult(rawResult)
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "getPlatformVersion":
            result.success("iOS " + UIDevice.current.systemVersion)

        case "getMediaPage":
            let type = PhotoLibraryScanner.ScanType.parse(args["type"] as? String)
            let exts = args["extensions"] as? [String] ?? []
            let page = intArg(args, "page", 0)
            let size = clamp(intArg(args, "pageSize", 100), 1, 500)
            work.async {
                let rows = self.scanner.queryPage(
                    type: type, extensions: exts, offset: page * size, limit: size)
                result.success(rows)
            }

        case "getMediaCount":
            let type = PhotoLibraryScanner.ScanType.parse(args["type"] as? String)
            let exts = args["extensions"] as? [String] ?? []
            work.async { result.success(self.scanner.count(type: type, extensions: exts)) }

        case "getThumbnail":
            guard let source = (args["uri"] as? String) ?? (args["path"] as? String) else {
                result.error("INVALID_ARGUMENT", "uri/path required", nil)
                return
            }
            let w = intArg(args, "width", 256)
            let h = intArg(args, "height", w)
            let stamp = int64Arg(args, "dateModified", 0)
            let kind = args["kind"] as? String ?? "image"
            work.async {
                result.success(self.thumbs.thumbnail(
                    source: source, width: w, height: h, stamp: stamp, kind: kind))
            }

        case "clearThumbnailCache":
            work.async {
                self.thumbs.clear()
                result.success(true)
            }

        case "getDirectories":
            work.async { result.success(self.sandboxDirectories()) }

        case "getDirectoryContents":
            let path = (args["path"] as? String)
                ?? NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
                ?? NSHomeDirectory()
            let page = intArg(args, "page", 0)
            let size = clamp(intArg(args, "pageSize", 200), 1, 1000)
            work.async {
                do { result.success(try self.listDir(path: path, page: page, size: size)) }
                catch { result.error("FILE_ACCESS_ERROR", error.localizedDescription, nil) }
            }

        case "hasStoragePermission":
            result.success(isAuthorized())
        case "hasAllFilesAccess":
            result.success(isAuthorized())   // no "all files" concept on iOS
        case "requestStoragePermission":
            requestAuthorization { granted in result.success(granted) }
        case "openAllFilesAccessSettings":
            openAppSettings()
            result.success(true)

        default:
            result.notImplemented()
        }
    }

    // ─── Directory browsing (sandbox only) ──────────────────────────────────

    /// iOS apps only see their own container. We expose the Documents directory
    /// so directory-browsing APIs still work for files the app itself imported.
    private func sandboxDirectories() -> [[String: String]] {
        let fm = FileManager.default
        var out: [[String: String]] = []
        for (name, dir) in [("Documents", FileManager.SearchPathDirectory.documentDirectory),
                            ("Downloads", .downloadsDirectory)] {
            if let url = fm.urls(for: dir, in: .userDomainMask).first,
               fm.fileExists(atPath: url.path) {
                out.append(["name": name, "path": url.path])
            }
        }
        return out
    }

    private func listDir(path: String, page: Int, size: Int) throws -> [[String: Any]] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "device_media_finder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid directory: \(path)"])
        }
        let names = try fm.contentsOfDirectory(atPath: path)
        var entries: [[String: Any]] = []
        for name in names {
            let full = (path as NSString).appendingPathComponent(name)
            let attrs = try? fm.attributesOfItem(atPath: full)
            var entryIsDir: ObjCBool = false
            fm.fileExists(atPath: full, isDirectory: &entryIsDir)
            let modified = (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
            entries.append([
                "name": name,
                "path": full,
                "isDirectory": entryIsDir.boolValue,
                "size": (attrs?[.size] as? NSNumber)?.intValue ?? 0,
                "dateModified": Int(modified.timeIntervalSince1970 * 1000.0),
                "extension": entryIsDir.boolValue ? "" : extLower(name),
            ])
        }
        // Directories first, then case-insensitive alphabetical — a single
        // combined comparator so ordering is well-defined (sort isn't stable).
        entries.sort {
            let ad = $0["isDirectory"] as? Bool ?? false
            let bd = $1["isDirectory"] as? Bool ?? false
            if ad != bd { return ad }
            let an = ($0["name"] as? String ?? "").lowercased()
            let bn = ($1["name"] as? String ?? "").lowercased()
            return an < bn
        }
        let from = page * size
        if from >= entries.count { return [] }
        return Array(entries[from..<min(from + size, entries.count)])
    }

    // ─── Permissions ─────────────────────────────────────────────────────────

    private func isAuthorized() -> Bool {
        let status: PHAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }
        return status == .authorized || status == .limited
    }

    private func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        let handler: (PHAuthorizationStatus) -> Void = { status in
            completion(status == .authorized || status == .limited)
        }
        if #available(iOS 14.0, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: handler)
        } else {
            PHPhotoLibrary.requestAuthorization(handler)
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // ─── Argument helpers ─────────────────────────────────────────────────────

    private func intArg(_ args: [String: Any], _ key: String, _ def: Int) -> Int {
        (args[key] as? NSNumber)?.intValue ?? def
    }

    private func int64Arg(_ args: [String: Any], _ key: String, _ def: Int64) -> Int64 {
        (args[key] as? NSNumber)?.int64Value ?? def
    }

    private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }

    private func extLower(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        return ext.lowercased()
    }
}

/// Replies exactly once, always on the main thread, so background tasks can
/// never trigger a "Reply already submitted" crash — the Swift analogue of the
/// Android `SafeResult`.
private final class SafeResult {
    private var delegate: FlutterResult?
    private let lock = NSLock()

    init(_ delegate: @escaping FlutterResult) { self.delegate = delegate }

    func success(_ value: Any?) { post { $0(value) } }
    func error(_ code: String, _ message: String?, _ details: Any?) {
        post { $0(FlutterError(code: code, message: message, details: details)) }
    }
    func notImplemented() { post { $0(FlutterMethodNotImplemented) } }

    private func post(_ block: @escaping (FlutterResult) -> Void) {
        lock.lock()
        guard let d = delegate else { lock.unlock(); return }
        delegate = nil
        lock.unlock()
        DispatchQueue.main.async { block(d) }
    }
}
