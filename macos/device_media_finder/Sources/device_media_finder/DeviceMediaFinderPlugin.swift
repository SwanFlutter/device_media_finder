import Cocoa
import FlutterMacOS

/// macOS backend for the `device_media_finder` plugin.
///
/// Mirrors the Android `MethodChannel` contract exactly. Because macOS grants
/// file-system access, this backend follows the Android model closely: a
/// `FileSystemScanner` walks the user's media directories for images, video,
/// audio, documents and archives of any size/format, and directory browsing is
/// backed by the real file system. All heavy work runs on a background queue
/// and every reply is delivered once, on the main thread.
///
/// Sandbox note: an App-Store-sandboxed build only sees directories the user
/// has granted (e.g. via the `com.apple.security.files.user-selected` or the
/// Music/Movies/Pictures entitlements). A non-sandboxed build sees everything
/// the user account can read.
public class DeviceMediaFinderPlugin: NSObject, FlutterPlugin {

    private let scanner = FileSystemScanner()
    private let thumbs = ThumbnailEngine()
    private let work = DispatchQueue(label: "device_media_finder.io",
                                     qos: .userInitiated, attributes: .concurrent)

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "device_media_finder", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(DeviceMediaFinderPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result rawResult: @escaping FlutterResult) {
        let result = SafeResult(rawResult)
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "getPlatformVersion":
            result.success("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)

        case "getMediaPage":
            let type = FileSystemScanner.ScanType.parse(args["type"] as? String)
            let exts = args["extensions"] as? [String] ?? []
            let page = intArg(args, "page", 0)
            let size = clamp(intArg(args, "pageSize", 100), 1, 500)
            work.async {
                result.success(self.scanner.queryPage(
                    type: type, extensions: exts, offset: page * size, limit: size))
            }

        case "getMediaCount":
            let type = FileSystemScanner.ScanType.parse(args["type"] as? String)
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
            work.async { result.success(self.publicDirectories()) }

        case "getDirectoryContents":
            let path = (args["path"] as? String) ?? NSHomeDirectory()
            let page = intArg(args, "page", 0)
            let size = clamp(intArg(args, "pageSize", 200), 1, 1000)
            work.async {
                do { result.success(try self.listDir(path: path, page: page, size: size)) }
                catch { result.error("FILE_ACCESS_ERROR", error.localizedDescription, nil) }
            }

        // macOS has no runtime storage permission (file access is governed by
        // sandbox entitlements at build time), so these report "granted".
        case "hasStoragePermission", "hasAllFilesAccess", "requestStoragePermission":
            result.success(true)
        case "openAllFilesAccessSettings":
            result.success(true)

        default:
            result.notImplemented()
        }
    }

    // ─── Directory browsing ─────────────────────────────────────────────────

    private func publicDirectories() -> [[String: String]] {
        let fm = FileManager.default
        let entries: [(String, FileManager.SearchPathDirectory)] = [
            ("Desktop", .desktopDirectory),
            ("Documents", .documentDirectory),
            ("Downloads", .downloadsDirectory),
            ("Movies", .moviesDirectory),
            ("Music", .musicDirectory),
            ("Pictures", .picturesDirectory),
        ]
        var out: [[String: String]] = [["name": "Home", "path": NSHomeDirectory()]]
        for (name, dir) in entries {
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
                "extension": entryIsDir.boolValue ? "" : (name as NSString).pathExtension.lowercased(),
            ])
        }
        // Directories first, then alphabetical (case-insensitive) — matches the
        // Android `listDir` ordering.
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

    // ─── Argument helpers ─────────────────────────────────────────────────────

    private func intArg(_ args: [String: Any], _ key: String, _ def: Int) -> Int {
        (args[key] as? NSNumber)?.intValue ?? def
    }

    private func int64Arg(_ args: [String: Any], _ key: String, _ def: Int64) -> Int64 {
        (args[key] as? NSNumber)?.int64Value ?? def
    }

    private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }
}

/// Replies exactly once, always on the main thread — the Swift analogue of the
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
