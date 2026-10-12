import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_media_finder_platform_interface.dart';
import 'src/media_item.dart';
import 'src/media_type.dart';

/// An implementation of [DeviceMediaFinderPlatform] that uses method channels.
class MethodChannelDeviceMediaFinder extends DeviceMediaFinderPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('device_media_finder');

  @override
  Future<String?> getPlatformVersion() {
    return methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  @override
  Future<int> getMediaCount({
    required MediaType type,
    List<String> extensions = const [],
  }) async {
    final count = await methodChannel.invokeMethod<int>('getMediaCount', {
      'type': type.name,
      'extensions': extensions,
    });
    return count ?? 0;
  }

  @override
  Future<List<MediaItem>> getMediaPage({
    required MediaType type,
    required int page,
    required int pageSize,
    List<String> extensions = const [],
  }) async {
    final raw = await methodChannel.invokeMethod<List<dynamic>>(
      'getMediaPage',
      {
        'type': type.name,
        'extensions': extensions,
        'page': page,
        'pageSize': pageSize,
      },
    );
    if (raw == null) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(MediaItem.fromMap)
        .toList(growable: false);
  }

  @override
  Future<String?> getThumbnail({
    required String uriOrPath,
    required int width,
    int? height,
    int dateModified = 0,
    String kind = 'image',
  }) {
    return methodChannel.invokeMethod<String>('getThumbnail', {
      'uri': uriOrPath,
      'width': width,
      'height': height ?? width,
      'dateModified': dateModified,
      'kind': kind,
    });
  }

  @override
  Future<bool> clearThumbnailCache() async {
    final ok = await methodChannel.invokeMethod<bool>('clearThumbnailCache');
    return ok ?? false;
  }

  @override
  Future<bool> hasStoragePermission() async {
    final ok = await methodChannel.invokeMethod<bool>('hasStoragePermission');
    return ok ?? false;
  }

  @override
  Future<bool> requestStoragePermission() async {
    final ok = await methodChannel.invokeMethod<bool>(
      'requestStoragePermission',
    );
    return ok ?? false;
  }

  @override
  Future<bool> hasAllFilesAccess() async {
    final ok = await methodChannel.invokeMethod<bool>('hasAllFilesAccess');
    return ok ?? false;
  }

  @override
  Future<bool> openAllFilesAccessSettings() async {
    final ok = await methodChannel.invokeMethod<bool>(
      'openAllFilesAccessSettings',
    );
    return ok ?? false;
  }

  @override
  Future<List<Map<String, String>>> getDirectories() async {
    final raw = await methodChannel.invokeMethod<List<dynamic>>(
      'getDirectories',
    );
    if (raw == null) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((m) {
          return m.map((k, v) => MapEntry('$k', '$v'));
        })
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getDirectoryContents({
    required String path,
    int page = 0,
    int pageSize = 200,
  }) async {
    final raw = await methodChannel.invokeMethod<List<dynamic>>(
      'getDirectoryContents',
      {'path': path, 'page': page, 'pageSize': pageSize},
    );
    if (raw == null) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((m) {
          return m.map((k, v) => MapEntry('$k', v));
        })
        .toList(growable: false);
  }
}
