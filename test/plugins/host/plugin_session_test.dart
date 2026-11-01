import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/plugins/plugin_bundle.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/domain/plugins/plugin_snapshot.dart';
import 'package:photoframe/plugins/host/plugin_session.dart';
import 'package:photoframe/platform/paths.dart';

import '../../data/plugins/plugin_test_support.dart';

class _FakeClock implements Clock {
  _FakeClock([DateTime? start])
    : _now = start ?? DateTime.utc(2026, 11, 1, 12);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

class _Sender {
  final List<String> messages = <String>[];

  /// When set, the next send waits for this completer.
  Completer<void>? gate;

  Future<void> send(String json) async {
    messages.add(json);
    final current = gate;
    if (current != null) {
      gate = null;
      await current.future;
    }
  }

  List<Map<String, dynamic>> decoded() {
    return <Map<String, dynamic>>[
      for (final message in messages)
        jsonDecode(message) as Map<String, dynamic>,
    ];
  }

  Map<String, dynamic> last() => decoded().last;

  int countType(String type) {
    return decoded().where((message) => message['type'] == type).length;
  }

  void clear() => messages.clear();
}

Map<String, dynamic> _payload(Map<String, dynamic> message) {
  final value = message['payload'];
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

final Map<String, dynamic> _empty = <String, dynamic>{};

PluginSnapshotSource _source(
  DateTime now, {
  double progress = 0.5,
  PluginMediaSnapshot? media,
}) {
  return PluginSnapshotSource(
    appVersion: '1.0.0',
    pluginApiVersion: supportedPluginApiVersion,
    locale: 'en-US',
    timeZone: 'Europe/Berlin',
    theme: 'dark',
    viewportWidth: 1920,
    viewportHeight: 1080,
    nightMode: false,
    now: now,
    playback: PluginPlaybackSnapshot(
      playing: true,
      index: 0,
      total: 1,
      intervalSeconds: 15,
      progress: progress,
      muted: false,
      slideshowRunning: true,
    ),
    media: media,
    config: _empty,
    placement: const PluginPlacement(width: 320, height: 160),
    enabled: true,
    visible: true,
  );
}

Future<PluginManifest> _install(
  PluginStore store, {
  String id = 'com.example.test',
  List<String>? actions,
  List<String>? inputs,
  bool network = false,
  Map<String, dynamic>? settings,
}) async {
  final bundle = PluginBundleValidator().validate(
    buildBundleZip(
      manifest: sampleManifest(
        id: id,
        actions: actions,
        inputs: inputs,
        settings: settings,
        permissions: <String, dynamic>{'network': network},
      ),
    ),
    installedIds: const <String>{},
    hostApiVersion: supportedPluginApiVersion,
    hostAppVersion: '2.0.0',
  );
  final installed = await store.install(
    bundle,
    enabled: true,
    source: pluginSourceZip,
  );
  return installed.manifest;
}

PluginSession _session({
  required PluginStore store,
  required PluginManifest manifest,
  required _Sender sender,
  required _FakeClock clock,
  List<PluginAction>? actions,
  List<Map<String, dynamic>>? actionPayloads,
  List<Uri>? links,
  List<String>? logs,
  List<MapEntry<String, bool>>? errors,
  List<PluginPlacement>? placements,
}) {
  return PluginSession(
    pluginId: manifest.id,
    manifest: manifest,
    store: store,
    clock: clock,
    sendMessage: sender.send,
    onAction: (action, payload) {
      actions?.add(action);
      actionPayloads?.add(payload);
    },
    onOpenLink: (uri) => links?.add(uri),
    onLog: (level, message) => logs?.add('$level:$message'),
    onError: (message, disable) => errors?.add(MapEntry(message, disable)),
    onPlacementRequest: (placement) => placements?.add(placement),
  );
}

Future<void> _send(
  PluginSession session,
  String type, {
  Map<String, dynamic>? payload,
  String? id,
}) {
  final message = <String, dynamic>{
    'type': type,
    'id': ?id,
    'payload': ?payload,
  };
  return session.handleMessage(jsonEncode(message));
}

void main() {
  late Directory temporary;
  late AppDatabase database;
  late PluginStore store;
  late _FakeClock clock;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('photoframe_session_');
    database = AppDatabase(NativeDatabase.memory());
    store = PluginStore(database, InMemoryAppPaths(temporary));
    await store.init();
    clock = _FakeClock();
  });

  tearDown(() async {
    await database.close();
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('start sends an initial state with stored config', () async {
    final manifest = await _install(
      store,
      inputs: <String>['config', 'placement'],
    );
    await store.setConfig(manifest.id, <String, dynamic>{'format': '24h'});

    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );
    session.setSnapshotSource(_source(clock.now()));

    await session.start();

    final message = sender.last();
    expect(message['type'], 'state');
    final payload = _payload(message);
    expect(payload['app'], isA<Map<String, dynamic>>());
    expect(payload['time'], isA<Map<String, dynamic>>());
    expect(
      (payload['config'] as Map<String, dynamic>)['format'],
      '24h',
    );
  });

  test('ready and getState send state envelopes', () async {
    final manifest = await _install(store, inputs: <String>['config']);
    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );
    session.setSnapshotSource(_source(clock.now()));

    await _send(session, 'ready', id: 'ready-1');
    expect(sender.last()['type'], 'state');
    expect(sender.last()['id'], 'ready-1');

    await _send(session, 'getState', id: 'state-1');
    expect(sender.countType('state'), 2);
    expect(sender.last()['id'], 'state-1');
  });

  test('getConfig sends the stored config and keeps it for state', () async {
    final manifest = await _install(store, inputs: <String>['config']);
    await store.setConfig(manifest.id, <String, dynamic>{'format': '24h'});

    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );
    session.setSnapshotSource(_source(clock.now()));

    await _send(session, 'getConfig', id: 'config-1');
    expect(sender.last()['type'], 'config');
    expect(sender.last()['id'], 'config-1');
    expect(_payload(sender.last()), <String, dynamic>{'format': '24h'});

    await store.setConfig(manifest.id, <String, dynamic>{'format': '12h'});
    await _send(session, 'getConfig');

    await _send(session, 'getState');
    final config = _payload(sender.last())['config'] as Map<String, dynamic>;
    expect(config['format'], '12h');
  });

  test('storage set/get/remove/clear persists JSON values', () async {
    final manifest = await _install(store);
    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );

    await _send(
      session,
      'storage.set',
      payload: <String, dynamic>{'key': 'text', 'value': '"hello"'},
      id: 'set-1',
    );
    expect(sender.last()['type'], 'storageResult');
    expect(_payload(sender.last())['ok'], isTrue);
    expect(_payload(sender.last())['value'], '"hello"');
    expect(await store.storageGet(manifest.id, 'text'), '"hello"');

    await _send(
      session,
      'storage.set',
      payload: <String, dynamic>{
        'key': 'object',
        'value': <String, dynamic>{'a': 1},
      },
    );
    expect(await store.storageGet(manifest.id, 'object'), '{"a":1}');

    await _send(
      session,
      'storage.get',
      payload: <String, dynamic>{'key': 'object'},
    );
    expect(_payload(sender.last())['value'], '{"a":1}');

    await _send(
      session,
      'storage.remove',
      payload: <String, dynamic>{'key': 'text'},
    );
    expect(await store.storageGet(manifest.id, 'text'), isNull);

    await _send(
      session,
      'storage.clear',
      payload: <String, dynamic>{},
    );
    expect(await store.storageGet(manifest.id, 'object'), isNull);

    await _send(
      session,
      'storage.get',
      payload: <String, dynamic>{'key': ''},
    );
    expect(_payload(sender.last())['ok'], isFalse);
    expect(_payload(sender.last())['error'], isNotNull);
  });

  test('actions require declaration, grant, and stay rate limited', () async {
    final manifest = await _install(
      store,
      actions: <String>['next', 'openSettings'],
    );
    final sender = _Sender();
    final actions = <PluginAction>[];
    final actionPayloads = <Map<String, dynamic>>[];
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
      actions: actions,
      actionPayloads: actionPayloads,
    );

    await _send(
      session,
      'action',
      payload: <String, dynamic>{'name': 'next'},
    );
    expect(_payload(sender.last())['ok'], isFalse);
    expect(_payload(sender.last())['error'], contains('not granted'));

    session.setGrantedActions(<PluginAction>{PluginAction.next});
    await _send(
      session,
      'action',
      payload: <String, dynamic>{
        'name': 'next',
        'payload': <String, dynamic>{'step': 1},
      },
    );
    expect(_payload(sender.last())['ok'], isTrue);
    expect(actions, <PluginAction>[PluginAction.next]);
    expect(actionPayloads.single, <String, dynamic>{'step': 1});

    await _send(
      session,
      'action',
      payload: <String, dynamic>{'name': 'openSettings'},
    );
    expect(_payload(sender.last())['ok'], isFalse);

    await _send(
      session,
      'action',
      payload: <String, dynamic>{'name': 'bogus'},
    );
    expect(_payload(sender.last())['ok'], isFalse);

    // One call is already recorded; nine more fill the ten-per-minute window.
    for (var index = 0; index < 9; index++) {
      await _send(
        session,
        'action',
        payload: <String, dynamic>{'name': 'next'},
      );
      expect(_payload(sender.last())['ok'], isTrue, reason: '$index');
    }
    await _send(
      session,
      'action',
      payload: <String, dynamic>{'name': 'next'},
    );
    expect(_payload(sender.last())['ok'], isFalse);
    expect(_payload(sender.last())['error'], contains('rate limit'));
    expect(actions.length, 10);
  });

  test('openLink validates URLs before calling the host', () async {
    final manifest = await _install(store);
    final sender = _Sender();
    final links = <Uri>[];
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
      links: links,
    );

    await _send(
      session,
      'openLink',
      payload: <String, dynamic>{'url': 'javascript:alert(1)'},
    );
    expect(_payload(sender.last())['ok'], isFalse);
    expect(links, isEmpty);

    await _send(
      session,
      'openLink',
      payload: <String, dynamic>{'url': 'https://user:pass@example.com/'},
    );
    expect(_payload(sender.last())['ok'], isFalse);
    expect(links, isEmpty);

    await _send(
      session,
      'openLink',
      payload: <String, dynamic>{'url': 'https://example.com/path'},
    );
    expect(_payload(sender.last())['ok'], isTrue);
    expect(links.single.toString(), 'https://example.com/path');
  });

  test('requestPlacement validates, persists, and notifies', () async {
    final manifest = await _install(store);
    final sender = _Sender();
    final placements = <PluginPlacement>[];
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
      placements: placements,
    );

    await _send(
      session,
      'requestPlacement',
      payload: <String, dynamic>{
        'x': 0.1,
        'y': 0.2,
        'width': 400,
        'height': 200,
        'anchor': 'bottom-end',
        'zOrder': 4,
        'showDuringNight': true,
      },
      id: 'placement-1',
    );

    expect(sender.last()['type'], 'placement');
    expect(sender.last()['id'], 'placement-1');
    final placement = placements.single;
    expect(placement.anchor, PluginAnchor.bottomEnd);
    expect(placement.x, 0.1);
    expect(placement.y, 0.2);
    expect(placement.width, 400);
    expect(placement.height, 200);
    expect(placement.zOrder, 4);
    expect(placement.showDuringNight, isTrue);

    final stored = await store.getPlacement(manifest.id);
    expect(stored.width, 400);
    expect(stored.x, 0.1);
    expect(stored.y, 0.2);

    await _send(
      session,
      'requestPlacement',
      payload: <String, dynamic>{'x': 2.0, 'width': 100, 'height': 100},
    );
    expect(sender.last()['type'], 'error');
    expect(placements.length, 1);
    expect((await store.getPlacement(manifest.id)).width, 400);
  });

  test('unknown and malformed messages become bounded errors', () async {
    final manifest = await _install(store);
    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );

    await _send(session, 'deleteEverything');
    expect(sender.last()['type'], 'error');
    expect(_payload(sender.last())['code'], 'invalid_message');

    await session.handleMessage('{');
    expect(sender.last()['type'], 'error');
    expect(_payload(sender.last())['code'], 'invalid_message');

    await session.handleMessage('[]');
    expect(sender.last()['type'], 'error');

    const secret = 'TOP-SECRET-VALUE';
    await session.handleMessage(
      '{"type":"log","payload":{"message":"$secret"',
    );
    for (final message in sender.messages) {
      expect(message, isNot(contains(secret)));
    }
  });

  test('network request is denied without permission', () async {
    final manifest = await _install(store, network: false);
    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );

    await _send(
      session,
      'network.request',
      payload: <String, dynamic>{'url': 'https://example.com/'},
    );

    expect(sender.last()['type'], 'error');
    expect(_payload(sender.last())['code'], 'network_denied');
    expect(sender.countType('networkResult'), 0);
  });

  test('network policy rejects local, credentialed, and bad methods', () async {
    final manifest = await _install(store, network: true);
    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );

    await _send(
      session,
      'network.request',
      payload: <String, dynamic>{'url': 'http://127.0.0.1/'},
    );
    expect(sender.last()['type'], 'networkResult');
    expect(_payload(sender.last())['ok'], isFalse);
    expect(_payload(sender.last())['error'], contains('not allowed'));

    await _send(
      session,
      'network.request',
      payload: <String, dynamic>{
        'url': 'https://user:pass@example.com/',
      },
    );
    expect(_payload(sender.last())['ok'], isFalse);

    // The method is rejected before any connection is opened.
    await _send(
      session,
      'network.request',
      payload: <String, dynamic>{
        'url': 'https://example.com/',
        'method': 'TRACE',
      },
    );
    expect(_payload(sender.last())['ok'], isFalse);
    expect(_payload(sender.last())['error'], contains('method'));
  });

  test('requestUpdate is coalesced to one per second', () async {
    final manifest = await _install(store, inputs: <String>['config']);
    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );
    session.setSnapshotSource(_source(clock.now()));

    await _send(session, 'requestUpdate');
    expect(sender.countType('state'), 1);

    await _send(session, 'requestUpdate');
    expect(sender.countType('state'), 1);

    clock.advance(const Duration(milliseconds: 999));
    await _send(session, 'requestUpdate');
    expect(sender.countType('state'), 1);

    clock.advance(const Duration(milliseconds: 1));
    await _send(session, 'requestUpdate');
    expect(sender.countType('state'), 2);
  });

  test('ticks resend changed slideshow progress', () async {
    final manifest = await _install(store, inputs: <String>['playback']);
    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );
    session.setVisible(true);
    session.setSnapshotSource(_source(clock.now(), progress: 0.2));

    await session.tick();
    var playback = _payload(sender.last())['playback'] as Map<String, dynamic>;
    expect(playback['progress'], 0.2);

    session.setSnapshotSource(_source(clock.now(), progress: 0.75));
    await session.tick();
    playback = _payload(sender.last())['playback'] as Map<String, dynamic>;
    expect(playback['progress'], 0.75);
    expect(sender.countType('state'), 2);
  });

  test('loading config keeps the background media snapshot', () async {
    final manifest = await _install(
      store,
      inputs: <String>['config', 'media'],
    );
    await store.setConfig(manifest.id, <String, dynamic>{'cornerRadius': 3});
    const media = PluginMediaSnapshot(
      hasSession: true,
      title: 'Track',
      artist: 'Artist',
      playing: true,
      canPrevious: true,
      canNext: true,
    );

    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );
    session.setSnapshotSource(_source(clock.now(), media: media));

    await _send(session, 'getConfig');
    await _send(session, 'getState');

    final payload = _payload(sender.last());
    final config = payload['config'] as Map<String, dynamic>;
    expect(config['cornerRadius'], 3);
    final sent = payload['media'] as Map<String, dynamic>;
    expect(sent['hasSession'], isTrue);
    expect(sent['title'], 'Track');
    expect(sent['artist'], 'Artist');
    expect(sent['playing'], isTrue);
  });

  test('ticks require visibility and activity and skip in-flight sends',
      () async {
    final manifest = await _install(store, inputs: <String>['config']);
    final sender = _Sender();
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
    );
    session.setSnapshotSource(_source(clock.now()));

    await session.tick();
    expect(sender.messages, isEmpty);

    session.setVisible(true);
    await session.tick();
    expect(sender.countType('state'), 1);

    sender.messages.clear();
    final gate = Completer<void>();
    sender.gate = gate;
    final first = session.tick();
    await Future<void>.delayed(Duration.zero);
    expect(sender.messages.length, 1);

    await session.tick();
    expect(sender.messages.length, 1);

    gate.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(sender.messages.length, 2);

    session.setAppActive(false);
    await session.tick();
    expect(sender.messages.length, 2);

    session.startTicker();
    session.stopTicker();
    session.dispose();
  });

  test('three reportError failures within five minutes disable the plugin',
      () async {
    final manifest = await _install(store);
    final sender = _Sender();
    final errors = <MapEntry<String, bool>>[];
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
      errors: errors,
    );
    session.setSnapshotSource(_source(clock.now()));
    session.setVisible(true);
    session.setAppActive(true);

    for (var index = 0; index < 3; index++) {
      await _send(
        session,
        'reportError',
        payload: <String, dynamic>{'message': 'failure $index'},
      );
    }

    expect(errors.map((entry) => entry.value), <bool>[false, false, true]);
    expect(session.isFailed, isTrue);

    sender.clear();
    await session.tick();
    expect(sender.messages, isEmpty);
  });

  test('failures outside the five-minute window do not disable', () async {
    final manifest = await _install(store);
    final sender = _Sender();
    final errors = <MapEntry<String, bool>>[];
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
      errors: errors,
    );

    for (var index = 0; index < 3; index++) {
      await _send(
        session,
        'reportError',
        payload: <String, dynamic>{'message': 'failure $index'},
      );
      clock.advance(const Duration(minutes: 6));
    }

    expect(errors.map((entry) => entry.value), <bool>[false, false, false]);
    expect(session.isFailed, isFalse);
  });

  test('log and reportError are forwarded with levels', () async {
    final manifest = await _install(store);
    final sender = _Sender();
    final logs = <String>[];
    final errors = <MapEntry<String, bool>>[];
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
      logs: logs,
      errors: errors,
    );

    await _send(
      session,
      'log',
      payload: <String, dynamic>{'level': 'warn', 'message': 'slow'},
    );
    expect(logs, <String>['warn:slow']);

    await _send(
      session,
      'reportError',
      payload: <String, dynamic>{'message': 'broken'},
    );
    expect(logs, contains('error:broken'));
    expect(errors.single.key, 'broken');
    expect(errors.single.value, isFalse);
  });

  test('dispose cancels timers and ignores later messages', () async {
    final manifest = await _install(store);
    final sender = _Sender();
    final logs = <String>[];
    final session = _session(
      store: store,
      manifest: manifest,
      sender: sender,
      clock: clock,
      logs: logs,
    );
    session.setSnapshotSource(_source(clock.now()));

    session.startTicker();
    session.dispose();

    await _send(
      session,
      'log',
      payload: <String, dynamic>{'level': 'info', 'message': 'ignored'},
    );

    expect(logs, isEmpty);
    expect(sender.messages, isEmpty);
  });
}
