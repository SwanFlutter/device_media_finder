import 'dart:typed_data';

import 'package:device_media_finder/src/models/audio_file.dart';
import 'package:device_media_finder/src/models/videofile.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'device_media_finder_method_channel.dart';

abstract class DeviceMediaFinderPlatform extends PlatformInterface {
  /// Constructs a DeviceMediaFinderPlatform.
  DeviceMediaFinderPlatform() : super(token: _token);

  static final Object _token = Object();

  static DeviceMediaFinderPlatform _instance = MethodChannelDeviceMediaFinder();

  /// The default instance of [DeviceMediaFinderPlatform] to use.
  ///
  /// Defaults to [MethodChannelDeviceMediaFinder].
  static DeviceMediaFinderPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DeviceMediaFinderPlatform] when
  /// they register themselves.
  static set instance(DeviceMediaFinderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Get a list of videos from the device
  Future<List<VideoFile>> getVideos() {
    throw UnimplementedError('getVideos() has not been implemented.');
  }

  /// Get a list of videos from the device filtered by MIME types
  ///
  /// [mimeTypes] is a list of MIME types to filter by (e.g. ["video/mp4", "video/3gpp"])
  /// You can also use wildcards like "video/*" to get all videos of a certain type
  Future<List<VideoFile>> getVideosByMimeType(List<String> mimeTypes) {
    throw UnimplementedError('getVideosByMimeType() has not been implemented.');
  }

  /// Get a list of audio files from the device
  Future<List<AudioFile>> getAudios() {
    throw UnimplementedError('getAudios() has not been implemented.');
  }

  /// Get a thumbnail for a video
  Future<Uint8List?> getVideoThumbnail(
    String videoId, {
    int width = 128,
    int height = 128,
  }) {
    throw UnimplementedError('getVideoThumbnail() has not been implemented.');
  }

  /// Get a list of folders containing videos
  ///
  /// Returns a map where the keys are folder paths and the values are the number of videos in each folder
  Future<Map<String, int>> getVideoFolders() {
    throw UnimplementedError('getVideoFolders() has not been implemented.');
  }
}
