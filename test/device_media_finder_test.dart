import 'dart:typed_data';

import 'package:device_media_finder/device_media_finder.dart';
import 'package:device_media_finder/device_media_finder_method_channel.dart';
import 'package:device_media_finder/device_media_finder_platform_interface.dart';
import 'package:device_media_finder/models/media_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceMediaFinderPlatform
    with MockPlatformInterfaceMixin
    implements DeviceMediaFinderPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<List<VideoFile>> getVideos() => Future.value([]);

  @override
  Future<List<VideoFile>> getVideosByMimeType(List<String> mimeTypes) =>
      Future.value([]);

  @override
  Future<List<AudioFile>> getAudios() => Future.value([]);

  @override
  Future<Uint8List?> getVideoThumbnail(
    String videoId, {
    int width = 128,
    int height = 128,
  }) => Future.value(null);
}

void main() {
  final DeviceMediaFinderPlatform initialPlatform =
      DeviceMediaFinderPlatform.instance;

  test('$MethodChannelDeviceMediaFinder is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDeviceMediaFinder>());
  });

  test('getPlatformVersion', () async {
    DeviceMediaFinder deviceMediaFinderPlugin = DeviceMediaFinder();
    MockDeviceMediaFinderPlatform fakePlatform =
        MockDeviceMediaFinderPlatform();
    DeviceMediaFinderPlatform.instance = fakePlatform;

    expect(await deviceMediaFinderPlugin.getPlatformVersion(), '42');
  });
}
