import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Background media metadata from the platform media session.
class BackgroundMediaState {
  const BackgroundMediaState({
    this.hasSession = false,
    this.title,
    this.artist,
    this.album,
    this.packageName,
    this.playing = false,
    this.canPrevious = false,
    this.canNext = false,
    this.positionSeconds,
    this.durationSeconds,
  });

  static const BackgroundMediaState none = BackgroundMediaState();

  final bool hasSession;
  final String? title;
  final String? artist;
  final String? album;
  final String? packageName;
  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final double? positionSeconds;
  final double? durationSeconds;

  factory BackgroundMediaState.fromMap(Object? value) {
    if (value is! Map) {
      return none;
    }
    return BackgroundMediaState(
      hasSession: value['hasSession'] == true,
      title: value['title'] as String?,
      artist: value['artist'] as String?,
      album: value['album'] as String?,
      packageName: value['packageName'] as String?,
      playing: value['playing'] == true,
      canPrevious: value['canPrevious'] == true,
      canNext: value['canNext'] == true,
      positionSeconds: (value['positionSeconds'] as num?)?.toDouble(),
      durationSeconds: (value['durationSeconds'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BackgroundMediaState &&
        other.hasSession == hasSession &&
        other.title == title &&
        other.artist == artist &&
        other.album == album &&
        other.packageName == packageName &&
        other.playing == playing &&
        other.canPrevious == canPrevious &&
        other.canNext == canNext &&
        other.positionSeconds == positionSeconds &&
        other.durationSeconds == durationSeconds;
  }

  @override
  int get hashCode => Object.hash(
    hasSession,
    title,
    artist,
    album,
    packageName,
    playing,
    canPrevious,
    canNext,
    positionSeconds,
    durationSeconds,
  );
}

enum MediaControl { previous, toggle, next }

abstract class MediaSessionService {
  Stream<BackgroundMediaState> get changes;
  Future<BackgroundMediaState> get current;
  Stream<BackgroundMediaState> watch();
  Future<bool> control(MediaControl control);
  Future<bool> get hasNotificationAccess;
  Future<void> openNotificationAccessSettings();
}

class PlatformMediaSessionService implements MediaSessionService {
  PlatformMediaSessionService({bool? android, bool? windows})
    : _android = android ?? Platform.isAndroid,
      _windows = windows ?? Platform.isWindows;

  static const MethodChannel _channel = MethodChannel(
    'com.rincew1nd.photoframe/media',
  );

  static const Duration _windowsPollInterval = Duration(seconds: 1);

  final bool _android;
  final bool _windows;
  final StreamController<BackgroundMediaState> _events =
      StreamController<BackgroundMediaState>.broadcast();
  bool _handlerInstalled = false;

  bool get _supported => _android || _windows;

  @override
  Stream<BackgroundMediaState> get changes => _events.stream;

  @override
  Future<BackgroundMediaState> get current async {
    if (!_supported) {
      return BackgroundMediaState.none;
    }
    if (_android) {
      _installHandler();
    }
    try {
      return BackgroundMediaState.fromMap(
        await _channel.invokeMethod<Object?>('getMediaState'),
      );
    } on Object {
      return BackgroundMediaState.none;
    }
  }

  @override
  Stream<BackgroundMediaState> watch() async* {
    if (_android) {
      _installHandler();
      yield await current;
      yield* _events.stream;
      return;
    }
    if (!_windows) {
      yield BackgroundMediaState.none;
      return;
    }
    // ponytail: GSMTC has no Dart event stream here; 1 Hz polling is enough
    // for the plugin state tick.
    while (true) {
      yield await current;
      await Future<void>.delayed(_windowsPollInterval);
    }
  }

  @override
  Future<bool> control(MediaControl control) async {
    if (!_supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('mediaControl', <String, Object?>{
            'action': control.name,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> get hasNotificationAccess async {
    if (_windows) {
      return true;
    }
    if (!_android) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('hasNotificationAccess') ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> openNotificationAccessSettings() async {
    if (_windows) {
      return;
    }
    if (!_android) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('openNotificationAccessSettings');
    } on Object {
      return;
    }
  }

  void _installHandler() {
    if (_handlerInstalled) {
      return;
    }
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'mediaState') {
        _events.add(BackgroundMediaState.fromMap(call.arguments));
      }
      return null;
    });
  }
}

class UnsupportedMediaSessionService implements MediaSessionService {
  const UnsupportedMediaSessionService();

  @override
  Stream<BackgroundMediaState> get changes =>
      const Stream<BackgroundMediaState>.empty();

  @override
  Future<BackgroundMediaState> get current async => BackgroundMediaState.none;

  @override
  Stream<BackgroundMediaState> watch() async* {
    yield BackgroundMediaState.none;
  }

  @override
  Future<bool> control(MediaControl control) async => false;

  @override
  Future<bool> get hasNotificationAccess async => false;

  @override
  Future<void> openNotificationAccessSettings() async {}
}
