
import 'package:flutter/foundation.dart';
import 'package:photoframe/core/logging/app_logger.dart';

class CrashHandler {
  const CrashHandler._();

  static void install(AppLogger logger) {
    FlutterError.onError = (details) {
      logger.error(
        'Unhandled Flutter error: ${details.exceptionAsString()}',
        error: details.exception,
        stackTrace: details.stack,
      );
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      logger.error(
        'Unhandled platform error',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    };
  }
}
