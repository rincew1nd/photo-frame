import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/plugins/host/plugin_bridge.dart';

class _MutableClock implements Clock {
  _MutableClock(this._now);

  DateTime _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  @override
  DateTime now() => _now;
}

Matcher _validationError(String fragment) {
  return throwsA(
    isA<PluginValidationException>().having(
      (error) => error.message,
      'message',
      contains(fragment),
    ),
  );
}

void main() {
  group('PluginBridgeMessage', () {
    test('parses every supported inbound type', () {
      for (final type in PluginBridgeProtocol.inboundTypes) {
        final message = PluginBridgeMessage.parse('{"type":"$type"}');
        expect(message.type, type);
        expect(message.id, isNull);
        expect(message.payload, isEmpty);
      }
    });

    test('parses id and payload', () {
      final message = PluginBridgeMessage.parse(
        '{"type":"storage.set","id":"call-1","payload":'
        '{"key":"x","value":"{\\"a\\":1}"}}',
      );

      expect(message.type, 'storage.set');
      expect(message.id, 'call-1');
      expect(message.payload['key'], 'x');
      expect(message.payload['value'], '{"a":1}');
    });

    test('rejects malformed JSON, non-objects, and bad fields', () {
      expect(
        () => PluginBridgeMessage.parse('{'),
        _validationError('not valid JSON'),
      );
      expect(
        () => PluginBridgeMessage.parse('[]'),
        _validationError('must be a JSON object'),
      );
      expect(
        () => PluginBridgeMessage.parse('"log"'),
        _validationError('must be a JSON object'),
      );
      expect(
        () => PluginBridgeMessage.parse('{}'),
        _validationError('type must be a non-empty string'),
      );
      expect(
        () => PluginBridgeMessage.parse('{"type":5}'),
        _validationError('type must be a non-empty string'),
      );
      expect(
        () => PluginBridgeMessage.parse('{"type":"  "}'),
        _validationError('type must be a non-empty string'),
      );
      expect(
        () => PluginBridgeMessage.parse('{"type":"log","id":5}'),
        _validationError('id must be a non-empty string'),
      );
      expect(
        () => PluginBridgeMessage.parse('{"type":"log","id":""}'),
        _validationError('id must be a non-empty string'),
      );
      expect(
        () => PluginBridgeMessage.parse('{"type":"log","payload":[]}'),
        _validationError('payload must be an object'),
      );
    });

    test('rejects unknown message types', () {
      expect(
        () => PluginBridgeMessage.parse('{"type":"deleteEverything"}'),
        _validationError('Unsupported plugin bridge message type'),
      );
    });

    test('rejects oversized messages without echoing them', () {
      final oversize =
          '{"type":"log","payload":{"message":"'
          '${'a' * (PluginBridgeProtocol.maxMessageBytes + 1)}"}}';

      expect(
        oversize.length,
        greaterThan(PluginBridgeProtocol.maxMessageBytes),
      );
      expect(
        () => PluginBridgeMessage.parse(oversize),
        _validationError('exceeds the 65536-byte limit'),
      );
    });
  });

  group('PluginBridgeProtocol', () {
    test('allowlist matches the manifest action enum', () {
      expect(
        PluginBridgeProtocol.allowedActions,
        PluginAction.values.map((action) => action.name).toSet(),
      );
      for (final action in PluginAction.values) {
        expect(PluginBridgeProtocol.isAllowedAction(action.name), isTrue);
      }
      expect(PluginBridgeProtocol.isAllowedAction('launchMissiles'), isFalse);
    });

    test('encodes outbound envelopes', () {
      final decoded = jsonDecode(
        PluginBridgeProtocol.state(<String, dynamic>{
          'app': <String, dynamic>{},
        }, id: 'state-1'),
      ) as Map<String, dynamic>;
      expect(decoded['type'], 'state');
      expect(decoded['id'], 'state-1');
      expect(decoded['payload'], <String, dynamic>{'app': <String, dynamic>{}});

      final event = jsonDecode(
        PluginBridgeProtocol.event(<String, dynamic>{'kind': 'image'}),
      ) as Map<String, dynamic>;
      expect(event['type'], 'event');
      expect(event['payload'], <String, dynamic>{'kind': 'image'});

      final action = jsonDecode(
        PluginBridgeProtocol.actionResult(
          action: 'next',
          ok: true,
          id: 'call-1',
        ),
      ) as Map<String, dynamic>;
      expect(action['type'], 'actionResult');
      expect(action['id'], 'call-1');
      expect(action['payload'], <String, dynamic>{
        'action': 'next',
        'ok': true,
        'result': null,
        'error': null,
      });

      final log = jsonDecode(
        PluginBridgeProtocol.log(level: 'warn', message: 'slow'),
      ) as Map<String, dynamic>;
      expect(log['type'], 'log');
      expect(log['payload'], <String, dynamic>{
        'level': 'warn',
        'message': 'slow',
      });

      final error = jsonDecode(
        PluginBridgeProtocol.error(message: 'failed', code: 'E1'),
      ) as Map<String, dynamic>;
      expect(error['type'], 'error');
      expect(error['payload'], <String, dynamic>{
        'message': 'failed',
        'code': 'E1',
      });

      expect(
        PluginBridgeProtocol.outboundTypes.contains(
          (jsonDecode(PluginBridgeProtocol.config(<String, dynamic>{}))
              as Map<String, dynamic>)['type'],
        ),
        isTrue,
      );
    });
  });

  group('PluginActionRateLimiter', () {
    test('allows ten calls per minute by default and denies the eleventh', () {
      final clock = _MutableClock(DateTime.utc(2026, 11, 1));
      final limiter = PluginActionRateLimiter(clock: clock);

      for (var index = 0; index < 10; index++) {
        expect(limiter.allow('com.example.a'), isTrue, reason: '$index');
      }
      expect(limiter.allow('com.example.a'), isFalse);

      // Windows are per plugin.
      expect(limiter.allow('com.example.b'), isTrue);
    });

    test('refills after the window and honors a custom limit', () {
      final clock = _MutableClock(DateTime.utc(2026, 11, 1));
      final limiter = PluginActionRateLimiter(
        limit: 2,
        window: const Duration(seconds: 30),
        clock: clock,
      );

      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('a'), isFalse);

      clock.advance(const Duration(seconds: 29));
      expect(limiter.allow('a'), isFalse);

      clock.advance(const Duration(seconds: 1));
      expect(limiter.allow('a'), isTrue);
    });

    test('reset clears one plugin window', () {
      final clock = _MutableClock(DateTime.utc(2026, 11, 1));
      final limiter = PluginActionRateLimiter(limit: 1, clock: clock);

      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('a'), isFalse);

      limiter.reset('a');
      expect(limiter.allow('a'), isTrue);

      expect(limiter.allow('b'), isTrue);
      limiter.resetAll();
      expect(limiter.allow('b'), isTrue);
    });
  });

  group('PluginLinkPolicy', () {
    const policy = PluginLinkPolicy();

    test('allows and normalizes http and https', () {
      expect(policy.isAllowed('https://example.com/a'), isTrue);
      expect(policy.isAllowed('http://example.com'), isTrue);
      expect(policy.isAllowed('  https://example.com/path  '), isTrue);
      expect(policy.isAllowed('HTTPS://Example.COM/Path'), isTrue);

      final normalized = policy.normalize('https://example.com/a/../b');
      expect(normalized, isNotNull);
      expect(normalized.toString(), 'https://example.com/b');
    });

    test('blocks non-http schemes and malformed URLs', () {
      for (final url in <String>[
        'file:///C:/Windows/win.ini',
        'javascript:alert(1)',
        'intent://scan/#Intent;end',
        'data:text/html,<b>x</b>',
        'ftp://example.com/file',
        'about:blank',
        'not a url',
        '://example.com',
        'http://',
        '',
        'https://example.com/\nnext',
      ]) {
        expect(policy.normalize(url), isNull, reason: url);
        expect(policy.isAllowed(url), isFalse, reason: url);
      }
    });

    test('blocks credentials in links', () {
      expect(policy.normalize('https://user:pass@example.com'), isNull);
    });
  });

  group('PluginNetworkPolicy', () {
    const policy = PluginNetworkPolicy();

    test('exposes bounded defaults', () {
      expect(PluginNetworkPolicy.defaultTimeout, const Duration(seconds: 10));
      expect(PluginNetworkPolicy.defaultMaxResponseBytes, 1024 * 1024);
      expect(PluginNetworkPolicy.defaultRequestsPerMinute, 30);
      expect(policy.timeout, PluginNetworkPolicy.defaultTimeout);
      expect(
        policy.maxResponseBytes,
        PluginNetworkPolicy.defaultMaxResponseBytes,
      );
      expect(
        policy.requestsPerMinute,
        PluginNetworkPolicy.defaultRequestsPerMinute,
      );
    });

    test('allows public http and https hosts', () {
      for (final url in <String>[
        'https://example.com/path?q=1',
        'http://8.8.8.8/',
        'https://1.1.1.1',
        'https://user-images.githubusercontent.com/x.png',
      ]) {
        expect(policy.validate(url), isNotNull, reason: url);
        expect(policy.isAllowed(url), isTrue, reason: url);
      }
    });

    test('rejects loopback, link-local, and private hosts', () {
      for (final url in <String>[
        'http://localhost/',
        'http://LOCALHOST./',
        'http://app.localhost/',
        'http://printer.local/',
        'http://0.0.0.0/',
        'http://127.0.0.1/',
        'http://127.1.2.3/',
        'http://10.0.0.1/',
        'http://172.16.0.1/',
        'http://172.31.255.255/',
        'http://192.168.1.1/',
        'http://169.254.1.1/',
        'http://100.64.0.1/',
        'http://[::1]/',
        'http://[fe80::1]/',
        'http://[fc00::1]/',
        'http://[::ffff:127.0.0.1]/',
      ]) {
        expect(policy.validate(url), isNull, reason: url);
        expect(policy.isAllowed(url), isFalse, reason: url);
      }
    });

    test('rejects credentials, non-http schemes, and malformed URLs', () {
      for (final url in <String>[
        'https://user:pass@example.com/',
        'ftp://example.com/',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'data:text/plain,hello',
        'not a url',
        'http://',
        'https://example.com/\n',
      ]) {
        expect(policy.validate(url), isNull, reason: url);
      }
    });
  });
}
