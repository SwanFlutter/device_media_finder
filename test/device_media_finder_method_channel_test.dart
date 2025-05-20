import 'package:device_media_finder/device_media_finder_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelDeviceMediaFinder platform = MethodChannelDeviceMediaFinder();
  const MethodChannel channel = MethodChannel('device_media_finder');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'getPlatformVersion':
              return '42';
            case 'getVideos':
              return [];
            case 'getAudios':
              return [];
            case 'getVideoThumbnail':
              return Uint8List(0);
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('getVideos', () async {
    expect(await platform.getVideos(), []);
  });

  test('getAudios', () async {
    expect(await platform.getAudios(), []);
  });

  test('getVideoThumbnail', () async {
    final result = await platform.getVideoThumbnail('test');
    expect(result != null, true);
  });
}
