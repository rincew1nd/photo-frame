import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/platform/paths.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

abstract class LivePhotoBounceSupport {
  Future<bool> get supported;
}

class PlatformLivePhotoBounceSupport implements LivePhotoBounceSupport {
  const PlatformLivePhotoBounceSupport();

  @override
  Future<bool> get supported async => !Platform.isAndroid;
}

class WakelockKeepAwake implements KeepAwakeService {
  const WakelockKeepAwake();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();

  @override
  Future<bool> get isEnabled => WakelockPlus.enabled;
}

class WindowManagerFullscreen implements FullscreenService {
  const WindowManagerFullscreen();

  @override
  Future<void> enable() => WindowManager.instance.setFullScreen(true);

  @override
  Future<void> disable() => WindowManager.instance.setFullScreen(false);
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

  final AppPaths _paths;
  RandomAccessFile? _lock;

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
      return true;
    } on FileSystemException {
      await handle.close();
      return false;
    }
  }

  @override
  Future<void> release() async {
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

class PlatformServices {
  const PlatformServices({
    required this.keepAwake,
    required this.fullscreen,
    required this.biometrics,
    required this.singleInstance,
    required this.livePhotoBounce,
  });

  final KeepAwakeService keepAwake;
  final FullscreenService fullscreen;
  final BiometricsService biometrics;
  final SingleInstanceService singleInstance;
  final LivePhotoBounceSupport livePhotoBounce;

  factory PlatformServices.create(AppPaths paths) {
    final fullscreen = Platform.isWindows || Platform.isLinux
        ? const WindowManagerFullscreen()
        : Platform.isAndroid
        ? const AndroidFullscreen()
        : const UnsupportedFullscreen();
    return PlatformServices(
      keepAwake: const WakelockKeepAwake(),
      fullscreen: fullscreen,
      biometrics: LocalAuthBiometrics(),
      singleInstance: FileLockSingleInstance(paths),
      livePhotoBounce: const PlatformLivePhotoBounceSupport(),
    );
  }
}
