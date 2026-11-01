import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photoframe/plugins/host/host_server.dart';
import 'package:webview_cef/webview_cef.dart' as cef;
import 'package:webview_flutter/webview_flutter.dart' as wf;

/// Which native renderer backs [PluginWebView] on the current platform.
enum PluginWebViewAdapter {
  /// System WebView through `webview_flutter`.
  android,

  /// Off-screen CEF through `webview_cef`.
  desktopCef,

  /// No supported renderer; [PluginWebView] reports an error.
  unsupported,
}

/// Picks the adapter without touching a platform channel, so it is testable.
PluginWebViewAdapter pluginWebViewAdapterFor(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => PluginWebViewAdapter.android,
    TargetPlatform.windows || TargetPlatform.linux =>
      PluginWebViewAdapter.desktopCef,
    _ => PluginWebViewAdapter.unsupported,
  };
}

/// A transparent, parent-sized plugin host view for one [PluginHostServer].
///
/// Loads [hostUri] only: the trusted host page embeds [entryUri] in its
/// sandboxed iframe. The widget does not manage the server or slideshow
/// placement yet; those belong to M5.
class PluginWebView extends StatefulWidget {
  const PluginWebView({
    super.key,
    required this.hostUri,
    this.entryUri,
    this.onLog,
    this.onMessage,
    this.onReady,
    this.onError,
    this.loadTimeout = const Duration(seconds: 10),
  });

  PluginWebView.server({
    super.key,
    required PluginHostServer server,
    this.onLog,
    this.onMessage,
    this.onReady,
    this.onError,
    this.loadTimeout = const Duration(seconds: 10),
  }) : hostUri = server.hostUri,
       entryUri = server.entryUri;

  final Uri hostUri;
  final Uri? entryUri;
  final ValueChanged<String>? onLog;
  final ValueChanged<String>? onMessage;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  final Duration loadTimeout;

  @override
  State<PluginWebView> createState() => PluginWebViewState();
}

class PluginWebViewState extends State<PluginWebView> {
  final PluginWebViewAdapter _adapter = pluginWebViewAdapterFor(
    defaultTargetPlatform,
  );

  wf.WebViewController? _androidController;
  cef.WebViewController? _cefController;
  Timer? _timeout;
  bool _finished = false;
  bool _disposed = false;
  bool _cefSessionActive = false;
  final List<String> _outbound = <String>[];

  /// Sends a JSON message to the trusted host page.
  Future<void> sendMessage(String json) async {
    if (_disposed || json.length > 65536) {
      return;
    }
    if (!_finished) {
      _outbound.add(json);
      if (_outbound.length > 100) {
        _outbound.removeAt(0);
      }
      return;
    }
    await _deliver(json);
  }

  Future<void> _deliver(String json) async {
    final call = 'window.pluginHostBridge && '
        'window.pluginHostBridge.receive(${jsonEncode(json)});';
    try {
      final android = _androidController;
      if (android != null) {
        await android.runJavaScript(call);
        return;
      }
      final cefController = _cefController;
      if (cefController != null) {
        await cefController.executeJavaScript(call);
      }
    } catch (error) {
      _log('Plugin message delivery failed: $error');
    }
  }

  void _flushOutbound() {
    if (_outbound.isEmpty) {
      return;
    }
    final messages = List<String>.of(_outbound);
    _outbound.clear();
    for (final message in messages) {
      unawaited(_deliver(message));
    }
  }

  @override
  void initState() {
    super.initState();
    _timeout = Timer(widget.loadTimeout, () {
      _fail('Timed out after ${widget.loadTimeout.inSeconds}s.');
    });
    switch (_adapter) {
      case PluginWebViewAdapter.android:
        unawaited(_initAndroid());
      case PluginWebViewAdapter.desktopCef:
        unawaited(_initCef());
      case PluginWebViewAdapter.unsupported:
        _fail('Plugin web views are not supported on $defaultTargetPlatform.');
    }
  }

  Future<void> _initAndroid() async {
    try {
      final controller = wf.WebViewController()
        ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          wf.NavigationDelegate(
            onPageFinished: (_) => _ready(),
            onWebResourceError: (error) {
              if (error.isForMainFrame != false) {
                _fail('WebView load failed: ${error.description}');
              }
            },
          ),
        )
        ..setOnConsoleMessage(
          (message) => widget.onLog?.call(
            '[${message.level.name}] ${message.message}',
          ),
        )
        ..addJavaScriptChannel(
          'PhotoFrameHost',
          onMessageReceived: (message) {
            final value = message.message;
            if (value.length <= 65536) {
              widget.onMessage?.call(value);
            }
          },
        );
      if (_disposed) {
        return;
      }
      _androidController = controller;
      setState(() {});
      await controller.loadRequest(widget.hostUri);
    } catch (error) {
      _fail('WebView initialization failed: $error');
    }
  }

  Future<void> _initCef() async {
    try {
      await _CefSession.acquire();
    } catch (error) {
      _fail('CEF initialization failed: $error');
      return;
    }
    if (_disposed || !mounted) {
      await _CefSession.release();
      return;
    }
    _cefSessionActive = true;

    try {
      final controller = cef.WebviewManager().createWebView(
        loading: const SizedBox.expand(),
      );
      _cefController = controller;
      controller.setWebviewListener(
        cef.WebviewEventsListener(
          onLoadEnd: (_, _) => _ready(),
          onConsoleMessage: (level, message, source, line) =>
              widget.onLog?.call('[$level] $message ($source:$line)'),
        ),
      );
      setState(() {});
      await controller.initialize(widget.hostUri.toString());
      await controller.setJavaScriptChannels({
        cef.JavascriptChannel(
          name: 'PhotoFrameHost',
          onMessageReceived: (message) {
            final value = message.message;
            if (value.length <= 65536) {
              widget.onMessage?.call(value);
            }
          },
        ),
      });
    } catch (error) {
      _fail('CEF initialization failed: $error');
    }
  }

  void _log(String message) => widget.onLog?.call(message);

  void _ready() {
    if (_finished || _disposed) {
      return;
    }
    _finished = true;
    _timeout?.cancel();
    _log('Plugin host loaded: ${widget.hostUri}');
    widget.onReady?.call();
    _flushOutbound();
  }

  void _fail(String message) {
    if (_finished || _disposed) {
      return;
    }
    _finished = true;
    _timeout?.cancel();
    _log(message);
    widget.onError?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    // webview_flutter 4.x has no controller-level dispose; removing the
    // WebViewWidget releases the platform view.
    _androidController = null;
    final controller = _cefController;
    _cefController = null;
    unawaited(_disposeCef(controller));
    super.dispose();
  }

  Future<void> _disposeCef(cef.WebViewController? controller) async {
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (error) {
        _log('CEF dispose failed: $error');
      }
    }
    if (_cefSessionActive) {
      _cefSessionActive = false;
      await _CefSession.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_adapter) {
      case PluginWebViewAdapter.android:
        final controller = _androidController;
        return controller == null
            ? const SizedBox.expand()
            : wf.WebViewWidget(controller: controller);
      case PluginWebViewAdapter.desktopCef:
        final controller = _cefController;
        return controller == null
            ? const SizedBox.expand()
            : ValueListenableBuilder<bool>(
                valueListenable: controller,
                builder: (context, ready, _) => ready
                    ? controller.webviewWidget
                    : const SizedBox.expand(),
              );
      case PluginWebViewAdapter.unsupported:
        return const SizedBox.expand();
    }
  }
}

/// Process-wide CEF lifetime guard: initialize once, quit when the last view
/// goes away.
///
/// ponytail: the software pixel-buffer path is used because the GPU
/// shared-texture path fails Flutter external-texture creation on the verified
/// host. Flip WEBVIEW_CEF_GPU_TEXTURE in third_party/webview_cef once the host
/// supports it.
class _CefSession {
  static int _active = 0;
  static Future<void>? _initialization;

  static Future<void> acquire() async {
    _active++;
    try {
      await (_initialization ??= cef.WebviewManager().initialize());
    } catch (_) {
      _initialization = null;
      _active--;
      rethrow;
    }
  }

  static Future<void> release() async {
    if (_active > 0) {
      _active--;
    }
    if (_active > 0) {
      return;
    }
    _initialization = null;
    try {
      await cef.WebviewManager().quit();
    } catch (_) {
      // Shutdown is best effort; CEF may already be gone.
    }
  }
}
