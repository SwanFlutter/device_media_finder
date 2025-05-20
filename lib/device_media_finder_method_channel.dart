import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_media_finder_platform_interface.dart';
import 'models/media_file.dart';

/// An implementation of [DeviceMediaFinderPlatform] that uses method channels.
class MethodChannelDeviceMediaFinder extends DeviceMediaFinderPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('device_media_finder');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<List<VideoFile>> getVideos() async {
    final List<dynamic> result = await methodChannel.invokeMethod('getVideos');
    return result
        .cast<Map<dynamic, dynamic>>()
        .map((map) => VideoFile.fromMap(Map<String, dynamic>.from(map)))
        .toList();
  }

  @override
  Future<List<VideoFile>> getVideosByMimeType(List<String> mimeTypes) async {
    final List<dynamic> result = await methodChannel.invokeMethod(
      'getVideosByMimeType',
      {'mimeTypes': mimeTypes},
    );
    return result
        .cast<Map<dynamic, dynamic>>()
        .map((map) => VideoFile.fromMap(Map<String, dynamic>.from(map)))
        .toList();
  }

  @override
  Future<List<AudioFile>> getAudios() async {
    final List<dynamic> result = await methodChannel.invokeMethod('getAudios');
    return result
        .cast<Map<dynamic, dynamic>>()
        .map((map) => AudioFile.fromMap(Map<String, dynamic>.from(map)))
        .toList();
  }

  @override
  Future<Uint8List?> getVideoThumbnail(
    String videoId, {
    int width = 128,
    int height = 128,
  }) async {
    final Uint8List? result = await methodChannel.invokeMethod(
      'getVideoThumbnail',
      {'videoId': videoId, 'width': width, 'height': height},
    );
    return result;
  }
}
