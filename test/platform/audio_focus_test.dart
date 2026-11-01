import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/platform/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.rincew1nd.photoframe/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'requestAudioFocus') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('overlapping leases abandon only after the last release', () async {
    final focus = PlatformAudioFocus(android: true);

    expect(await focus.request(), isTrue);
    expect(await focus.request(), isTrue);

    await focus.abandon();
    expect(calls.where((m) => m == 'abandonAudioFocus'), isEmpty);

    await focus.abandon();
    expect(calls.where((m) => m == 'abandonAudioFocus'), hasLength(1));
  });

  test('permanent loss resets the lease', () async {
    final focus = PlatformAudioFocus(android: true);

    expect(await focus.request(), isTrue);
    expect(calls.where((m) => m == 'requestAudioFocus'), hasLength(1));

    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('audioFocusChanged', 'lost'),
      ),
      (_) {},
    );

    expect(await focus.request(), isTrue);
    expect(calls.where((m) => m == 'requestAudioFocus'), hasLength(2));
  });
}
