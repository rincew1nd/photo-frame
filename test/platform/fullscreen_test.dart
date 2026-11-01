import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/platform/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isMinimized') {
        return false;
      }
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'desktop fullscreen uses native fullscreen once per transition',
    () async {
      final fullscreen = WindowManagerFullscreen(windows: false);

      await fullscreen.enable();
      await fullscreen.enable();
      final enabled = calls.where((call) => call.method == 'setFullScreen');
      expect(enabled, hasLength(1));
      expect(enabled.single.arguments, <String, Object?>{'isFullScreen': true});
      expect(calls.where((call) => call.method == 'show'), hasLength(1));

      await fullscreen.disable();
      await fullscreen.disable();
      final disabled = calls.where((call) => call.method == 'setFullScreen');
      expect(disabled, hasLength(2));
      expect(disabled.last.arguments, <String, Object?>{'isFullScreen': false});
    },
  );

  test('windows fullscreen style is a visible popup without decorations', () {
    final style = fullscreenWindowStyle(0x14CA0000);

    expect(style & 0x80000000, isNot(0));
    expect(style & 0x10000000, isNot(0));
    expect(style & 0x00C00000, 0);
    expect(style & 0x00040000, 0);
    expect(style & 0x00080000, 0);
  });
}
