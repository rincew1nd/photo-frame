import 'dart:math';

import 'package:photoframe/data/immich/models.dart';

class SlideshowEngine {
  SlideshowEngine(
    List<ImmichAsset> assets, {
    Random? random,
    int intervalSeconds = 10,
    bool shuffle = false,
  }) : _source = List<ImmichAsset>.of(assets),
       _random = random ?? Random(),
       _intervalSeconds = _clampInterval(intervalSeconds),
       _shuffle = shuffle {
    _sequence = List<ImmichAsset>.of(_source);
    if (_shuffle) {
      _sequence.shuffle(_random);
    }
  }

  final List<ImmichAsset> _source;
  final Random _random;
  late List<ImmichAsset> _sequence;
  int _currentIndex = 0;
  bool _playing = true;
  bool _shuffle;
  int _intervalSeconds;
  Duration _elapsed = Duration.zero;
  Duration? _currentDuration;

  static int _clampInterval(int seconds) {
    if (seconds < 1) {
      return 1;
    }
    if (seconds > 3600) {
      return 3600;
    }
    return seconds;
  }

  List<ImmichAsset> get sequence => List<ImmichAsset>.unmodifiable(_sequence);
  int get currentIndex => _currentIndex;
  ImmichAsset? get current => hasItems ? _sequence[_currentIndex] : null;
  bool get playing => _playing;
  bool get hasItems => _sequence.isNotEmpty;
  bool get shuffle => _shuffle;
  int get intervalSeconds => _intervalSeconds;
  Duration get elapsed => _elapsed;
  int get total => _sequence.length;
  Duration? get currentDuration => _currentDuration;

  double get progress {
    if (!hasItems) {
      return 0;
    }
    final duration = _currentDuration ?? Duration(seconds: _intervalSeconds);
    final durationMicros = duration.inMicroseconds;
    if (durationMicros <= 0) {
      return 0;
    }
    return (_elapsed.inMicroseconds / durationMicros).clamp(0.0, 1.0);
  }

  bool next() => _move(1);

  bool previous() => _move(-1);

  void pause() {
    _playing = false;
  }

  void resume() {
    _playing = true;
  }

  void reset() {
    _currentIndex = 0;
    _elapsed = Duration.zero;
    _playing = true;
    _currentDuration = null;
  }

  void setInterval(int seconds) {
    _intervalSeconds = _clampInterval(seconds);
  }

  void setCurrentDuration(Duration? duration) {
    _currentDuration = duration != null && duration > Duration.zero
        ? duration
        : null;
  }

  void setShuffle(bool value) {
    if (_shuffle == value) {
      return;
    }
    _shuffle = value;
    _rebuildSequence();
  }

  void reorder(List<ImmichAsset> assets) {
    _source
      ..clear()
      ..addAll(assets);
    _rebuildSequence();
  }

  bool tick(Duration delta) {
    if (!_playing || !hasItems || delta <= Duration.zero) {
      return false;
    }
    _elapsed += delta;
    final interval =
        _currentDuration ?? Duration(seconds: _intervalSeconds);
    var advanced = false;
    while (_elapsed >= interval) {
      _elapsed -= interval;
      _currentIndex = (_currentIndex + 1) % _sequence.length;
      advanced = true;
    }
    if (advanced) {
      _currentDuration = null;
    }
    return advanced && _sequence.length > 1;
  }

  bool _move(int direction) {
    if (!hasItems) {
      return false;
    }
    final index = (_currentIndex + direction) % _sequence.length;
    final changed = index != _currentIndex;
    _currentIndex = index;
    _elapsed = Duration.zero;
    _currentDuration = null;
    return changed;
  }

  void _rebuildSequence() {
    _currentDuration = null;
    final currentId = current?.id;
    _sequence = List<ImmichAsset>.of(_source);
    if (_shuffle) {
      _sequence.shuffle(_random);
    }
    if (_sequence.isEmpty) {
      _currentIndex = 0;
      return;
    }
    if (currentId == null) {
      _currentIndex = 0;
      return;
    }
    final index = _sequence.indexWhere((asset) => asset.id == currentId);
    _currentIndex = index >= 0 ? index : _clampIndex(_currentIndex);
  }

  int _clampIndex(int index) {
    if (index < 0) {
      return 0;
    }
    if (index >= _sequence.length) {
      return _sequence.length - 1;
    }
    return index;
  }
}
