import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/platform/services.dart';

void main() {
  test('Android below Chromium 100 is unsupported', () {
    final support = webViewSupportFor(
      platform: TargetPlatform.android,
      chromeMajor: 92,
      versionName: '12.1.2.326',
    );

    expect(support.supported, isFalse);
    expect(support.message, contains('Chromium 92'));
  });

  test('Android at Chromium 100 is supported', () {
    final support = webViewSupportFor(
      platform: TargetPlatform.android,
      chromeMajor: 100,
    );

    expect(support.supported, isTrue);
  });

  test('Android without a usable WebView is unsupported', () {
    expect(
      webViewSupportFor(platform: TargetPlatform.android).supported,
      isFalse,
    );
  });

  test('desktop platforms are supported', () {
    expect(
      webViewSupportFor(platform: TargetPlatform.windows).supported,
      isTrue,
    );
    expect(webViewSupportFor(platform: TargetPlatform.linux).supported, isTrue);
  });

  test('other platforms are unsupported', () {
    expect(webViewSupportFor(platform: TargetPlatform.iOS).supported, isFalse);
  });
}
