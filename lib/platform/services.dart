import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/platform/paths.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

abstract class KeepAwakeService {
  Future<void> enable();
  Future<void> disable();
  Future<bool> get isEnabled;
}

abstract class FullscreenService {
  Future<void> enable();
  Future<void> disable();
}

abstract class BiometricsService {
  Future<bool> get canAuthenticate;
  Future<bool> authenticate(String reason);
}

abstract class SingleInstanceService {
  Future<bool> acquire();
  Future<void> release();
}

abstract class AutostartService {
  Future<bool> get supported;
  Future<void> setEnabled(bool enabled);
}

class PlatformAutostart implements AutostartService {
  const PlatformAutostart();

  static const MethodChannel _channel = MethodChannel(
    'com.rincew1nd.photoframe/platform',
  );

  @override
  Future<bool> get supported async {
    if (Platform.isWindows || Platform.isLinux) {
      return true;
    }
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('getAutostartSupported') ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (Platform.isWindows) {
      try {
        await Process.run(
          'reg',
          windowsAutostartArgs(Platform.resolvedExecutable, enabled),
        );
      } on Object {
        return;
      }
      return;
    }
    if (Platform.isLinux) {
      try {
        final config = Platform.environment['XDG_CONFIG_HOME'];
        final base = config != null && config.isNotEmpty
            ? config
            : p.join(Platform.environment['HOME'] ?? '', '.config');
        final directory = Directory(p.join(base, 'autostart'));
        final file = File(
          p.join(directory.path, 'com.rincew1nd.photoframe.desktop'),
        );
        if (enabled) {
          await directory.create(recursive: true);
          await file.writeAsString(
            linuxAutostartEntry(Platform.resolvedExecutable),
          );
        } else if (await file.exists()) {
          await file.delete();
        }
      } on Object {
        return;
      }
      return;
    }
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setStartOnBoot', <String, Object?>{
        'enabled': enabled,
      });
    } on Object {
      return;
    }
  }
}

List<String> windowsAutostartArgs(String executable, bool enabled) {
  const String key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  if (enabled) {
    return <String>[
      'add',
      key,
      '/v',
      'PhotoFrame',
      '/t',
      'REG_SZ',
      '/d',
      '"$executable"',
      '/f',
    ];
  }
  return <String>['delete', key, '/v', 'PhotoFrame', '/f'];
}

String linuxAutostartEntry(String executable) {
  return '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=Photo Frame\n'
      'Exec="$executable"\n'
      'X-GNOME-Autostart-enabled=true\n';
}

class UnsupportedAutostart implements AutostartService {
  const UnsupportedAutostart();

  @override
  Future<bool> get supported async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}
}

enum AudioFocusEvent { lost, transient, gain }

abstract class AudioFocusService {
  Future<bool> request();
  Future<void> abandon();
  Stream<AudioFocusEvent> get events;
}

class PlatformAudioFocus implements AudioFocusService {
  PlatformAudioFocus({bool? android})
    : _android = android ?? Platform.isAndroid;

  static const MethodChannel _channel = MethodChannel(
    'com.rincew1nd.photoframe/platform',
  );

  final bool _android;
  final StreamController<AudioFocusEvent> _events =
      StreamController<AudioFocusEvent>.broadcast();
  bool _handlerInstalled = false;
  int _leases = 0;
  bool _held = false;

  @override
  Stream<AudioFocusEvent> get events => _events.stream;

  @override
  Future<bool> request() async {
    if (!_android) {
      return true;
    }
    if (!_handlerInstalled) {
      _handlerInstalled = true;
      _channel.setMethodCallHandler(_onMethodCall);
    }
    if (_held) {
      _leases++;
      return true;
    }
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestAudioFocus') ?? false;
      if (granted) {
        _held = true;
        _leases = 1;
      }
      return granted;
    } on Object {
      return false;
    }
  }

  Future<Object?> _onMethodCall(MethodCall call) async {
    if (call.method != 'audioFocusChanged') {
      return null;
    }
    switch (call.arguments) {
      case 'lost':
        _held = false;
        _leases = 0;
        _events.add(AudioFocusEvent.lost);
      case 'transient':
        if (_held) {
          _events.add(AudioFocusEvent.transient);
        }
      case 'gain':
        if (_leases > 0) {
          _held = true;
          _events.add(AudioFocusEvent.gain);
        }
    }
    return null;
  }

  @override
  Future<void> abandon() async {
    if (!_android || !_held) {
      return;
    }
    if (_leases > 1) {
      _leases--;
      return;
    }
    _leases = 0;
    _held = false;
    try {
      await _channel.invokeMethod<void>('abandonAudioFocus');
    } on Object {
      return;
    }
  }
}

class UnsupportedAudioFocus implements AudioFocusService {
  const UnsupportedAudioFocus();

  @override
  Future<bool> request() async => true;

  @override
  Future<void> abandon() async {}

  @override
  Stream<AudioFocusEvent> get events => Stream<AudioFocusEvent>.empty();
}

abstract class PermissionsService {
  Future<bool> get batteryOptimizationIgnored;
  Future<void> requestBatteryOptimizationExemption();
  Future<void> openAutostartSettings();
  Future<void> openHomeSettings();
}

class PlatformPermissions implements PermissionsService {
  const PlatformPermissions();

  static const MethodChannel _channel = MethodChannel(
    'com.rincew1nd.photoframe/platform',
  );

  @override
  Future<bool> get batteryOptimizationIgnored async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
    } on Object {
      return;
    }
  }

  @override
  Future<void> openAutostartSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('openAutostartSettings');
    } on Object {
      return;
    }
  }

  @override
  Future<void> openHomeSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('openHomeSettings');
    } on Object {
      return;
    }
  }
}

class UnsupportedPermissions implements PermissionsService {
  const UnsupportedPermissions();

  @override
  Future<bool> get batteryOptimizationIgnored async => true;

  @override
  Future<void> requestBatteryOptimizationExemption() async {}

  @override
  Future<void> openAutostartSettings() async {}

  @override
  Future<void> openHomeSettings() async {}
}

abstract class KioskService {
  Future<void> enable();
  Future<void> disable();
}

class WindowManagerKiosk implements KioskService {
  const WindowManagerKiosk();

  @override
  Future<void> enable() async {
    final window = WindowManager.instance;
    await window.setAlwaysOnTop(true);
    if (Platform.isWindows) {
      setWindowsTopmost(await window.getId(), true);
    }
    await window.setSkipTaskbar(true);
    await window.setResizable(false);
    await window.setMovable(false);
    await window.setMinimizable(false);
    await window.setMaximizable(false);
    if (Platform.isWindows) {
      focusWindowsWindow(await window.getId());
    } else {
      await window.focus();
    }
  }

  @override
  Future<void> disable() async {
    final window = WindowManager.instance;
    await window.setAlwaysOnTop(false);
    if (Platform.isWindows) {
      setWindowsTopmost(await window.getId(), false);
    }
    await window.setSkipTaskbar(false);
    await window.setResizable(true);
    await window.setMovable(true);
    await window.setMinimizable(true);
    await window.setMaximizable(true);
  }
}

class UnsupportedKiosk implements KioskService {
  const UnsupportedKiosk();

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

abstract class BrightnessService {
  Future<void> setWindowBrightness(double? brightness);
}

class PlatformWindowBrightness implements BrightnessService {
  const PlatformWindowBrightness();

  static const MethodChannel _channel = MethodChannel(
    'com.rincew1nd.photoframe/platform',
  );

  @override
  Future<void> setWindowBrightness(double? brightness) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setBrightness', <String, Object?>{
        'brightness': brightness,
      });
    } on Object {
      return;
    }
  }
}

class UnsupportedBrightness implements BrightnessService {
  const UnsupportedBrightness();

  @override
  Future<void> setWindowBrightness(double? brightness) async {}
}

abstract class LivePhotoBounceSupport {
  Future<bool> get supported;
}

class PlatformLivePhotoBounceSupport implements LivePhotoBounceSupport {
  const PlatformLivePhotoBounceSupport();

  @override
  Future<bool> get supported async => !Platform.isAndroid;
}

List<String> linuxInhibitArgs() {
  return <String>[
    '--what=sleep:idle',
    '--mode=block',
    '--who=Photo Frame',
    '--why=Keep the photo frame awake',
    'sleep',
    'infinity',
  ];
}

class WakelockKeepAwake implements KeepAwakeService {
  bool _enabled = false;
  Process? _linuxInhibitor;
  bool _linuxFallback = false;

  @override
  Future<void> enable() async {
    if (Platform.isWindows) {
      win32.SetThreadExecutionState(
        win32.ES_CONTINUOUS |
            win32.ES_SYSTEM_REQUIRED |
            win32.ES_DISPLAY_REQUIRED,
      );
      _enabled = true;
      return;
    }
    if (Platform.isLinux) {
      try {
        _linuxInhibitor = await Process.start(
          'systemd-inhibit',
          linuxInhibitArgs(),
        );
        _linuxFallback = false;
        return;
      } on Object {
        _linuxFallback = true;
        await WakelockPlus.enable();
        return;
      }
    }
    await WakelockPlus.enable();
  }

  @override
  Future<void> disable() async {
    if (Platform.isWindows) {
      win32.SetThreadExecutionState(win32.ES_CONTINUOUS);
      _enabled = false;
      return;
    }
    if (Platform.isLinux) {
      final inhibitor = _linuxInhibitor;
      _linuxInhibitor = null;
      if (inhibitor != null) {
        inhibitor.kill();
        try {
          await inhibitor.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          inhibitor.kill(ProcessSignal.sigkill);
        }
      }
      if (_linuxFallback) {
        _linuxFallback = false;
        await WakelockPlus.disable();
      }
      return;
    }
    await WakelockPlus.disable();
  }

  @override
  Future<bool> get isEnabled async {
    if (Platform.isWindows) {
      return _enabled;
    }
    if (Platform.isLinux) {
      return _linuxInhibitor != null || _linuxFallback;
    }
    return WakelockPlus.enabled;
  }
}

class WindowManagerFullscreen implements FullscreenService {
  WindowManagerFullscreen({bool? windows})
    : _windows = windows ?? Platform.isWindows;

  final bool _windows;
  bool _enabled = false;
  int? _previousStyle;
  (int, int, int, int)? _previousRect;

  @override
  Future<void> enable() async {
    if (_enabled) {
      return;
    }
    _enabled = true;
    if (_windows) {
      await _enableWindows();
      return;
    }
    await WindowManager.instance.setFullScreen(true);
    await WindowManager.instance.show();
    await WindowManager.instance.focus();
  }

  @override
  Future<void> disable() async {
    if (!_enabled) {
      return;
    }
    _enabled = false;
    if (_windows) {
      await _disableWindows();
      return;
    }
    await WindowManager.instance.setFullScreen(false);
  }

  Future<void> _enableWindows() async {
    final window = WindowManager.instance;
    final id = await window.getId();
    final handle = win32.HWND(Pointer.fromAddress(id));
    final style = win32.GetWindowLongPtr(handle, win32.GWL_STYLE).value;
    final rect = ffi.calloc<win32.RECT>();
    final info = ffi.calloc<win32.MONITORINFO>();
    try {
      win32.GetWindowRect(handle, rect);
      _previousStyle = style;
      _previousRect = (
        rect.ref.left,
        rect.ref.top,
        rect.ref.right - rect.ref.left,
        rect.ref.bottom - rect.ref.top,
      );
      final monitor = win32.MonitorFromWindow(
        handle,
        win32.MONITOR_DEFAULTTONEAREST,
      );
      info.ref.cbSize = sizeOf<win32.MONITORINFO>();
      final hasMonitor = win32.GetMonitorInfo(monitor, info);
      final left = hasMonitor ? info.ref.rcMonitor.left : rect.ref.left;
      final top = hasMonitor ? info.ref.rcMonitor.top : rect.ref.top;
      final width = hasMonitor
          ? info.ref.rcMonitor.right - info.ref.rcMonitor.left
          : rect.ref.right - rect.ref.left;
      final height = hasMonitor
          ? info.ref.rcMonitor.bottom - info.ref.rcMonitor.top
          : rect.ref.bottom - rect.ref.top;
      win32.SetWindowLongPtr(
        handle,
        win32.GWL_STYLE,
        fullscreenWindowStyle(style),
      );
      win32.SetWindowPos(
        handle,
        win32.HWND_TOP,
        left,
        top,
        width,
        height,
        win32.SWP_FRAMECHANGED | win32.SWP_SHOWWINDOW,
      );
    } finally {
      ffi.calloc.free(rect);
      ffi.calloc.free(info);
    }
    await window.show();
    focusWindowsWindow(id);
  }

  Future<void> _disableWindows() async {
    final window = WindowManager.instance;
    final id = await window.getId();
    final handle = win32.HWND(Pointer.fromAddress(id));
    final style = _previousStyle;
    final rect = _previousRect;
    _previousStyle = null;
    _previousRect = null;
    if (style != null) {
      win32.SetWindowLongPtr(handle, win32.GWL_STYLE, style);
    }
    win32.SetWindowPos(
      handle,
      null,
      rect?.$1 ?? 0,
      rect?.$2 ?? 0,
      rect?.$3 ?? 0,
      rect?.$4 ?? 0,
      win32.SWP_FRAMECHANGED |
          win32.SWP_NOZORDER |
          (rect == null
              ? win32.SWP_NOMOVE | win32.SWP_NOSIZE
              : win32.SWP_SHOWWINDOW),
    );
    await window.show();
  }
}

void setWindowsTopmost(int id, bool topmost) {
  final handle = win32.HWND(Pointer.fromAddress(id));
  win32.SetWindowPos(
    handle,
    topmost ? win32.HWND_TOPMOST : win32.HWND_NOTOPMOST,
    0,
    0,
    0,
    0,
    win32.SWP_NOMOVE | win32.SWP_NOSIZE,
  );
}

void focusWindowsWindow(int id) {
  final handle = win32.HWND(Pointer.fromAddress(id));
  final foreground = win32.GetForegroundWindow();
  if (foreground == handle) {
    win32.SetForegroundWindow(handle);
    return;
  }
  final windowThread = win32.GetWindowThreadProcessId(handle, null);
  final foregroundThread = win32.GetWindowThreadProcessId(foreground, null);
  if (windowThread != 0 &&
      foregroundThread != 0 &&
      windowThread != foregroundThread) {
    win32.AttachThreadInput(windowThread, foregroundThread, true);
    win32.SetForegroundWindow(handle);
    win32.BringWindowToTop(handle);
    win32.AttachThreadInput(windowThread, foregroundThread, false);
    return;
  }
  win32.SetForegroundWindow(handle);
  win32.BringWindowToTop(handle);
}

int fullscreenWindowStyle(int style) {
  const caption = 0x00C00000;
  const thickFrame = 0x00040000;
  const minimizeBox = 0x00020000;
  const maximizeBox = 0x00010000;
  const systemMenu = 0x00080000;
  const popup = 0x80000000;
  const visible = 0x10000000;
  return (style &
          ~(caption | thickFrame | minimizeBox | maximizeBox | systemMenu)) |
      popup |
      visible;
}

class AndroidFullscreen implements FullscreenService {
  const AndroidFullscreen();

  @override
  Future<void> enable() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  @override
  Future<void> disable() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

class UnsupportedFullscreen implements FullscreenService {
  const UnsupportedFullscreen();

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

class LocalAuthBiometrics implements BiometricsService {
  LocalAuthBiometrics([LocalAuthentication? authentication])
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> get canAuthenticate async {
    try {
      return await _authentication.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    if (!await canAuthenticate) {
      return true;
    }
    try {
      return await _authentication.authenticate(localizedReason: reason);
    } on Object {
      return false;
    }
  }
}

class FileLockSingleInstance implements SingleInstanceService {
  FileLockSingleInstance(this._paths);

  static const String _portFileName = 'photo_frame.port';

  final AppPaths _paths;
  RandomAccessFile? _lock;
  ServerSocket? _server;
  StreamSubscription<Socket>? _subscription;
  File? _portFile;

  @override
  Future<bool> acquire() async {
    if (_lock != null) {
      return true;
    }
    final support = await _paths.support();
    final file = File(p.join(support.path, 'photo_frame.lock'));
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.lock(FileLock.exclusive);
      _lock = handle;
      if (Platform.isWindows || Platform.isLinux) {
        try {
          await _startServer(support);
        } on Object catch (_) {}
      }
      return true;
    } on FileSystemException {
      await handle.close();
      if (Platform.isWindows || Platform.isLinux) {
        await _signalFocus(support);
      }
      return false;
    }
  }

  Future<void> _startServer(Directory support) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _subscription = server.listen((socket) {
      socket.listen((data) {
        if (String.fromCharCodes(data).contains('focus')) {
          unawaited(_focusWindow());
        }
      }, onError: (Object _) {});
    });
    final portFile = File(p.join(support.path, _portFileName));
    _portFile = portFile;
    await portFile.writeAsString('${server.port}');
  }

  Future<void> _focusWindow() async {
    try {
      await WindowManager.instance.show();
      await WindowManager.instance.focus();
    } on Object {
      return;
    }
  }

  Future<void> _signalFocus(Directory support) async {
    try {
      final portFile = File(p.join(support.path, _portFileName));
      if (!await portFile.exists()) {
        return;
      }
      final port = int.tryParse((await portFile.readAsString()).trim());
      if (port == null) {
        return;
      }
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.write('focus\n');
      await socket.flush();
      await socket.close();
    } on Object {
      return;
    }
  }

  @override
  Future<void> release() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final server = _server;
    _server = null;
    await server?.close();
    final portFile = _portFile;
    _portFile = null;
    if (portFile != null) {
      await portFile.delete().catchError((Object _) => portFile);
    }
    final handle = _lock;
    _lock = null;
    if (handle == null) {
      return;
    }
    try {
      await handle.unlock();
    } on FileSystemException {
      return;
    } finally {
      await handle.close();
    }
  }
}

const int minPluginChromiumMajor = 100;

class WebViewSupport {
  const WebViewSupport({
    required this.supported,
    this.chromeMajor,
    this.versionName,
  });

  final bool supported;
  final int? chromeMajor;
  final String? versionName;

  String get message {
    if (supported) {
      return '';
    }
    final version = chromeMajor != null
        ? 'Chromium $chromeMajor'
        : versionName == null
        ? 'an unknown WebView version'
        : 'WebView $versionName';
    return 'Plugins require Android WebView/Chromium '
        '$minPluginChromiumMajor or newer. This device reports $version.';
  }
}

WebViewSupport webViewSupportFor({
  required TargetPlatform platform,
  int? chromeMajor,
  String? versionName,
}) {
  switch (platform) {
    case TargetPlatform.android:
      return WebViewSupport(
        supported: chromeMajor != null && chromeMajor >= minPluginChromiumMajor,
        chromeMajor: chromeMajor,
        versionName: versionName,
      );
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return const WebViewSupport(supported: true);
    default:
      return const WebViewSupport(supported: false);
  }
}

class PlatformWebViewInfo {
  const PlatformWebViewInfo();

  static const MethodChannel _channel = MethodChannel(
    'com.rincew1nd.photoframe/platform',
  );

  Future<WebViewSupport> read() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return webViewSupportFor(platform: defaultTargetPlatform);
    }
    try {
      final info = await _channel.invokeMapMethod<String, Object?>(
        'webViewInfo',
      );
      return webViewSupportFor(
        platform: TargetPlatform.android,
        chromeMajor: info?['chromeMajor'] as int?,
        versionName: info?['versionName'] as String?,
      );
    } on Object {
      return const WebViewSupport(supported: false);
    }
  }
}

class PlatformServices {
  const PlatformServices({
    required this.keepAwake,
    required this.fullscreen,
    required this.biometrics,
    required this.singleInstance,
    required this.autostart,
    required this.permissions,
    required this.kiosk,
    required this.brightness,
    required this.livePhotoBounce,
  });

  final KeepAwakeService keepAwake;
  final FullscreenService fullscreen;
  final BiometricsService biometrics;
  final SingleInstanceService singleInstance;
  final AutostartService autostart;
  final PermissionsService permissions;
  final KioskService kiosk;
  final BrightnessService brightness;
  final LivePhotoBounceSupport livePhotoBounce;

  factory PlatformServices.create(AppPaths paths) {
    final fullscreen = Platform.isWindows || Platform.isLinux
        ? WindowManagerFullscreen()
        : Platform.isAndroid
        ? const AndroidFullscreen()
        : const UnsupportedFullscreen();
    final kiosk = Platform.isWindows || Platform.isLinux
        ? const WindowManagerKiosk()
        : const UnsupportedKiosk();
    return PlatformServices(
      keepAwake: WakelockKeepAwake(),
      fullscreen: fullscreen,
      biometrics: LocalAuthBiometrics(),
      singleInstance: FileLockSingleInstance(paths),
      autostart: const PlatformAutostart(),
      permissions: const PlatformPermissions(),
      kiosk: kiosk,
      brightness: const PlatformWindowBrightness(),
      livePhotoBounce: const PlatformLivePhotoBounceSupport(),
    );
  }
}
