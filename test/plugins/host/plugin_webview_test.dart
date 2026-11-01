import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/plugins/host/plugin_webview.dart';

void main() {
  test('selects the native adapter per platform', () {
    expect(
      pluginWebViewAdapterFor(TargetPlatform.android),
      PluginWebViewAdapter.android,
    );
    expect(
      pluginWebViewAdapterFor(TargetPlatform.windows),
      PluginWebViewAdapter.desktopCef,
    );
    expect(
      pluginWebViewAdapterFor(TargetPlatform.linux),
      PluginWebViewAdapter.desktopCef,
    );
    expect(
      pluginWebViewAdapterFor(TargetPlatform.iOS),
      PluginWebViewAdapter.unsupported,
    );
    expect(
      pluginWebViewAdapterFor(TargetPlatform.macOS),
      PluginWebViewAdapter.unsupported,
    );
  });
}
