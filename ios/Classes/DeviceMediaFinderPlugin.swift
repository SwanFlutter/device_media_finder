import Flutter
import UIKit
import Photos
import AVFoundation
import MobileCoreServices

public class DeviceMediaFinderPlugin: NSObject, FlutterPlugin {
  private let cacheDirectory: URL
  private let thumbnailQueue = DispatchQueue(label: "com.example.device_media_finder.thumbnailQueue", qos: .userInitiated)

  override init() {
    let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
    cacheDirectory = URL(fileURLWithPath: cachePath).appendingPathComponent("media_thumbnails")

    super.init()

    // Create cache directory if it doesn't exist
    if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
      try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "device_media_finder", binaryMessenger: registrar.messenger())
    let instance = DeviceMediaFinderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "getVideos":
      checkPhotoLibraryPermission { [weak self] granted in
        guard let self = self else { return }
        if granted {
          self.fetchVideos(result: result)
        } else {
          result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library permission not granted", details: nil))
        }
      }
    case "getAudios":
      // iOS doesn't provide direct access to music files like Android
      // We'll use MPMediaLibrary in a real implementation
      // For now, return an empty array
      result([])
    case "getVideoThumbnail":
      guard let args = call.arguments as? [String: Any],
            let videoId = args["videoId"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "videoId is required", details: nil))
        return
      }

      let width = (args["width"] as? Int) ?? 128
      let height = (args["height"] as? Int) ?? 128

      checkPhotoLibraryPermission { [weak self] granted in
        guard let self = self else { return }
        if granted {
          self.getVideoThumbnail(videoId: videoId, width: width, height: height, result: result)
        } else {
          result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library permission not granted", details: nil))
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
    let status = PHPhotoLibrary.authorizationStatus()
    switch status {
    case .authorized, .limited:
      completion(true)
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization { newStatus in
        DispatchQueue.main.async {
          completion(newStatus == .authorized || newStatus == .limited)
        }
      }
    case .denied, .restricted:
      completion(false)
    @unknown default:
      completion(false)
    }
  }

  private func fetchVideos(result: @escaping FlutterResult) {
    let fetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

    let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
    var videos: [[String: Any]] = []

    fetchResult.enumerateObjects { (asset, index, stop) in
      let video: [String: Any] = [
        "id": asset.localIdentifier,
        "name": asset.value(forKey: "filename") as? String ?? "Unknown",
        "duration": Int(asset.duration * 1000), // Convert to milliseconds
        "size": 0, // Not directly available in iOS
        "path": "", // Not directly available in iOS
        "uri": "ph://\(asset.localIdentifier)",
        "dateAdded": Int(asset.creationDate?.timeIntervalSince1970 ?? 0),
        "mimeType": "video/mp4" // Assuming mp4, not directly available in iOS
      ]
      videos.append(video)
    }

    result(videos)
  }

  private func getVideoThumbnail(videoId: String, width: Int, height: Int, result: @escaping FlutterResult) {
    // Check if thumbnail is cached
    let cacheFileName = "video_\(videoId.replacingOccurrences(of: "/", with: "_")).jpg"
    let cacheFilePath = cacheDirectory.appendingPathComponent(cacheFileName)

    if FileManager.default.fileExists(atPath: cacheFilePath.path) {
      do {
        let data = try Data(contentsOf: cacheFilePath)
        result(data)
      } catch {
        result(FlutterError(code: "CACHE_ERROR", message: "Failed to read cached thumbnail: \(error.localizedDescription)", details: nil))
      }
      return
    }

    // Generate thumbnail
    thumbnailQueue.async { [weak self] in
      guard let self = self else { return }

      let fetchOptions = PHFetchOptions()
      let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [videoId], options: fetchOptions)

      guard let asset = fetchResult.firstObject else {
        DispatchQueue.main.async {
          result(FlutterError(code: "NOT_FOUND", message: "Video asset not found", details: nil))
        }
        return
      }

      let options = PHImageRequestOptions()
      options.deliveryMode = .highQualityFormat
      options.isNetworkAccessAllowed = true
      options.isSynchronous = false

      PHImageManager.default().requestImage(
        for: asset,
        targetSize: CGSize(width: width, height: height),
        contentMode: .aspectFill,
        options: options
      ) { image, info in
        guard let image = image else {
          DispatchQueue.main.async {
            result(FlutterError(code: "THUMBNAIL_ERROR", message: "Failed to generate thumbnail", details: nil))
          }
          return
        }

        guard let data = image.jpegData(compressionQuality: 0.9) else {
          DispatchQueue.main.async {
            result(FlutterError(code: "COMPRESSION_ERROR", message: "Failed to compress thumbnail", details: nil))
          }
          return
        }

        // Cache the thumbnail
        do {
          try data.write(to: cacheFilePath)
        } catch {
          print("Failed to cache thumbnail: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
          result(data)
        }
      }
    }
  }
}
