import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/core/logging/app_logger.dart';

void main() {
  group('Redactor', () {
    test('redacts x-api-key headers', () {
      final output = Redactor.redact('x-api-key: super-secret-key');
      expect(output, contains('[REDACTED]'));
      expect(output, isNot(contains('super-secret-key')));
    });

    test('redacts authorization headers', () {
      final output = Redactor.redact(
        'Authorization: Bearer abc.def.ghi',
      );
      expect(output, contains('Authorization: [REDACTED]'));
      expect(output, isNot(contains('abc.def.ghi')));
    });

    test('redacts bearer values', () {
      final output = Redactor.redact('request Bearer abc.def.ghi sent');
      expect(output, contains('Bearer [REDACTED]'));
      expect(output, isNot(contains('abc.def.ghi')));
    });

    test('redacts query and pair parameters', () {
      final output = Redactor.redact(
        'apiKey=one&token=two&secret=three',
      );
      expect(output, isNot(contains('one')));
      expect(output, isNot(contains('two')));
      expect(output, isNot(contains('three')));
      expect(output, contains('apiKey=[REDACTED]'));
      expect(output, contains('token=[REDACTED]'));
      expect(output, contains('secret=[REDACTED]'));
    });

    test('redacts registered secrets anywhere', () {
      final output = Redactor.redact(
        'value is hunter2 in the message',
        secrets: <String>{'hunter2'},
      );
      expect(output, isNot(contains('hunter2')));
      expect(output, contains('[REDACTED]'));
    });
  });

  test('AppLogger buffers redacted lines including registered secrets', () {
    final logger = AppLogger()
      ..registerSecret('registered-value')
      ..info('header x-api-key: header-value')
      ..error('Bearer bearer-value and registered-value');

    final lines = logger.recentLines;
    expect(lines, hasLength(2));
    expect(lines.join('\n'), isNot(contains('header-value')));
    expect(lines.join('\n'), isNot(contains('bearer-value')));
    expect(lines.join('\n'), isNot(contains('registered-value')));
    expect(lines.first, contains('[INFO]'));
    expect(lines.last, contains('[ERROR]'));
  });

  test('AppLogger keeps the newest 500 lines', () {
    final logger = AppLogger();
    for (var index = 0; index < 510; index++) {
      logger.info('line $index');
    }
    expect(logger.recentLines, hasLength(AppLogger.maxLines));
    expect(logger.recentLines.first, contains('line 10'));
    expect(logger.recentLines.last, contains('line 509'));
  });
}
