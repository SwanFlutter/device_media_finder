import 'package:device_media_finder/device_media_finder.dart';
import 'package:device_media_finder/device_media_finder_method_channel.dart';
import 'package:device_media_finder/device_media_finder_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceMediaFinderPlatform extends DeviceMediaFinderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<int> getMediaCount({
    required MediaType type,
    List<String> extensions = const [],
  }) =>
      Future.value(3);

  @override
  Future<List<MediaItem>> getMediaPage({
    required MediaType type,
    required int page,
    required int pageSize,
    List<String> extensions = const [],
  }) =>
      Future.value([
        MediaItem.fromMap({
          'id': 1,
          'uri': 'content://media/external/video/media/1',
          'name': 'clip.mp4',
          'size': 1024,
          'dateModified': 1700000000000,
          'mimeType': 'video/mp4',
          'mediaType': 3,
          'path': '/storage/emulated/0/Movies/clip.mp4',
          'width': 1920,
          'height': 1080,
          'duration': 42000,
        }),
      ]);
}

void main() {
  final DeviceMediaFinderPlatform initialPlatform =
      DeviceMediaFinderPlatform.instance;

  test('$MethodChannelDeviceMediaFinder is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDeviceMediaFinder>());
  });

  test('getPlatformVersion', () async {
    final plugin = DeviceMediaFinder();
    DeviceMediaFinderPlatform.instance = MockDeviceMediaFinderPlatform();
    expect(await plugin.getPlatformVersion(), '42');
  });

  test('getVideos delegates to getMediaPage', () async {
    final plugin = DeviceMediaFinder();
    DeviceMediaFinderPlatform.instance = MockDeviceMediaFinderPlatform();
    final videos = await plugin.getVideos();
    expect(videos, hasLength(1));
    expect(videos.first.name, 'clip.mp4');
    expect(videos.first.isVideo, isTrue);
    expect(videos.first.duration, 42000);
  });

  group('MediaItem', () {
    test('parses maps and derives kind from mediaType', () {
      final video = MediaItem.fromMap({'mediaType': 3, 'name': 'a.mkv'});
      final audio = MediaItem.fromMap({'mediaType': 2, 'name': 'b.flac'});
      expect(video.kind, 'video');
      expect(video.extension, 'mkv');
      expect(audio.kind, 'audio');
    });

    test('falls back to mimeType when mediaType is none', () {
      final item = MediaItem.fromMap({
        'mediaType': 0,
        'mimeType': 'audio/mpeg',
        'name': 'song.mp3',
      });
      expect(item.kind, 'audio');
      expect(item.isAudio, isTrue);
    });
  });
}
