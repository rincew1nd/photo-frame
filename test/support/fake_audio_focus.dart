import 'dart:async';

import 'package:photoframe/platform/services.dart';

class FakeAudioFocus implements AudioFocusService {
  final StreamController<AudioFocusEvent> _controller =
      StreamController<AudioFocusEvent>.broadcast();

  int requestCount = 0;
  int abandonCount = 0;
  bool granted = true;

  @override
  Stream<AudioFocusEvent> get events => _controller.stream;

  @override
  Future<bool> request() async {
    requestCount++;
    return granted;
  }

  @override
  Future<void> abandon() async {
    abandonCount++;
  }

  void emit(AudioFocusEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  Future<void> dispose() => _controller.close();
}
