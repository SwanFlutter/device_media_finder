import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'device_media_finder_method_channel.dart';
import 'src/media_item.dart';
import 'src/media_type.dart';

/// The interface that platform-specific implementations of
/// `device_media_finder` must implement.
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
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Total number of items matching [type] (and optional [extensions]).
  Future<int> getMediaCount({
    required MediaType type,
    List<String> extensions = const [],
  }) {
    throw UnimplementedError('getMediaCount() has not been implemented.');
  }

  /// One SQL-paginated page of media items. Only the requested page is loaded
  /// into memory — safe for libraries with tens of thousands of files.
  Future<List<MediaItem>> getMediaPage({
    required MediaType type,
    required int page,
    required int pageSize,
    List<String> extensions = const [],
  }) {
    throw UnimplementedError('getMediaPage() has not been implemented.');
  }

  /// Generates (or returns a cached) thumbnail and yields its on-disk JPEG
  /// path. Returns `null` when no thumbnail could be produced.
  Future<String?> getThumbnail({
    required String uriOrPath,
    required int width,
    int? height,
    int dateModified = 0,
    String kind = 'image',
  }) {
    throw UnimplementedError('getThumbnail() has not been implemented.');
  }

  /// Deletes every cached thumbnail from disk.
  Future<bool> clearThumbnailCache() {
    throw UnimplementedError('clearThumbnailCache() has not been implemented.');
  }

  Future<bool> hasStoragePermission() {
    throw UnimplementedError('hasStoragePermission() has not been implemented.');
  }

  Future<bool> requestStoragePermission() {
    throw UnimplementedError(
      'requestStoragePermission() has not been implemented.',
    );
  }

  Future<bool> hasAllFilesAccess() {
    throw UnimplementedError('hasAllFilesAccess() has not been implemented.');
  }

  Future<bool> openAllFilesAccessSettings() {
    throw UnimplementedError(
      'openAllFilesAccessSettings() has not been implemented.',
    );
  }

  /// Well-known public storage directories (DCIM, Movies, Music, ...).
  Future<List<Map<String, String>>> getDirectories() {
    throw UnimplementedError('getDirectories() has not been implemented.');
  }

  /// Paginated listing of the files/folders directly inside [path].
  Future<List<Map<String, dynamic>>> getDirectoryContents({
    required String path,
    int page = 0,
    int pageSize = 200,
  }) {
    throw UnimplementedError('getDirectoryContents() has not been implemented.');
  }
}
