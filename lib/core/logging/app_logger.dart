import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/platform/paths.dart';

/// Redacts secrets and authorization values from log text.
class Redactor {
  const Redactor._();

  static final RegExp _headerPattern = RegExp(
    r'\b(x-api-key|authorization)\s*:\s*[^\r\n]+',
    caseSensitive: false,
  );

  static final RegExp _pairPattern = RegExp(
    r'\b(api[_-]?key|token|secret)\s*=\s*[^\s,;&}\]]+',
    caseSensitive: false,
  );

  static final RegExp _bearerPattern = RegExp(
    r'\bBearer\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );

  /// Returns [input] with registered [secrets] and auth values masked.
  static String redact(String input, {Set<String> secrets = const {}}) {
    var output = input;

    for (final secret in secrets.toList()
      ..sort((a, b) => b.length.compareTo(a.length))) {
      if (secret.isNotEmpty) {
        output = output.replaceAll(secret, '[REDACTED]');
      }
    }

    output = output.replaceAllMapped(
      _headerPattern,
      (match) => '${match.group(1)}: [REDACTED]',
    );
    output = output.replaceAllMapped(
      _pairPattern,
      (match) => '${match.group(1)}=[REDACTED]',
    );
    output = output.replaceAll(_bearerPattern, 'Bearer [REDACTED]');

    return output;
  }
}

/// Buffers redacted log lines and writes them to a rotating file.
class AppLogger {
  AppLogger({this._clock = const SystemClock()}) {
    _logger.level = Level.ALL;
  }

  static const int maxLines = 500;
  static const int maxBytes = 2 * 1024 * 1024;

  final Clock _clock;
  final Logger _logger = Logger.detached('photoframe');
  final List<String> _lines = <String>[];
  final Set<String> _secrets = <String>{};

  StreamSubscription<LogRecord>? _subscription;
  File? _file;
  Future<void> _writeQueue = Future<void>.value();

  List<String> get recentLines => List<String>.unmodifiable(_lines);

  Future<void> init(AppPaths paths) async {
    final directory = await paths.logs();
    _file = File(p.join(directory.path, 'photo_frame.log'));
    await _subscription?.cancel();
    _subscription = _logger.onRecord.listen((record) {
      _enqueueWrite(record.message.toString());
    });
  }

  void registerSecret(String value) {
    if (value.isNotEmpty) {
      _secrets.add(value);
    }
  }

  void info(String message, {Object? error, StackTrace? stackTrace}) {
    _emit(Level.INFO, 'INFO', message, error, stackTrace);
  }

  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    _emit(Level.WARNING, 'WARNING', message, error, stackTrace);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _emit(Level.SEVERE, 'ERROR', message, error, stackTrace);
  }

  Future<void> flush() => _writeQueue;

  void _emit(
    Level level,
    String label,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final buffer = StringBuffer()
      ..write(_clock.now().toIso8601String())
      ..write(' [')
      ..write(label)
      ..write('] ')
      ..write(message);
    if (error != null) {
      buffer
        ..write(' | error: ')
        ..write(error);
    }
    if (stackTrace != null) {
      buffer
        ..write(' | stack: ')
        ..write(stackTrace);
    }

    final line = Redactor.redact(buffer.toString(), secrets: _secrets);
    _lines.add(line);
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    _logger.log(level, line);
  }

  void _enqueueWrite(String line) {
    final file = _file;
    if (file == null) {
      return;
    }
    _writeQueue = _writeQueue.then((_) async {
      await _rotateIfNeeded(file);
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    });
  }

  Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists()) {
      return;
    }
    final length = await file.length();
    if (length < maxBytes) {
      return;
    }

    final third = File('${file.path}.3');
    if (await third.exists()) {
      await third.delete();
    }
    for (var index = 2; index >= 1; index--) {
      final source = File('${file.path}.$index');
      if (await source.exists()) {
        await source.rename('${file.path}.${index + 1}');
      }
    }
    await file.rename('${file.path}.1');
  }
}
