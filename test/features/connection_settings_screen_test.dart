import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/connection_providers.dart' as conn;
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/immich/auth_service.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/secure/secure_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/features/settings/connection_settings_screen.dart';
import 'package:photoframe/l10n/app_localizations.dart';
import 'package:photoframe/platform/services.dart';

class _FakeBiometrics implements BiometricsService {
  _FakeBiometrics({this.allow = true});

  final bool allow;
  int calls = 0;
  String? reason;

  @override
  Future<bool> get canAuthenticate async => true;

  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    this.reason = reason;
    return allow;
  }
}

class _FakeConnectionController extends conn.ConnectionController {
  _FakeConnectionController(this.initial);

  final conn.ConnectionState initial;

  @override
  Future<conn.ConnectionState> build() async => initial;
}

PermissionReport _grantedReport() {
  return PermissionReport(
    permissions: <ImmichPermission, PermissionStatus>{
      for (final permission in ImmichPermission.values)
        permission: PermissionStatus.granted,
    },
    checkedAt: DateTime.utc(2026, 1, 1),
  );
}

conn.ConnectionState _connectedState() {
  final report = _grantedReport();
  return conn.ConnectionState(
    settings: AppSettings(
      connection: ConnectionSettings(
        serverUrl: 'https://photos.example.com/api',
        userId: 'user-1',
        userEmail: 'user@example.com',
        userName: 'Test User',
        permissions: <String, String>{
          for (final entry in report.permissions.entries)
            entry.key.jsonName: entry.value.name,
        },
        albumIds: const <String>{'album-1'},
        lastConnectedAt: report.checkedAt,
      ),
    ),
    report: report,
  );
}

Future<void> _pump(WidgetTester tester, {BiometricsService? biometrics}) async {
  final repository = InMemorySettingsRepository();
  final logger = AppLogger();
  final secure = MemorySecureStore(<String, String>{
    SecretKeys.immichApiKey: 'super-secret-key',
  });
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conn.connectionControllerProvider.overrideWith(
          () => _FakeConnectionController(_connectedState()),
        ),
        settingsRepositoryProvider.overrideWithValue(repository),
        cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
        appLoggerProvider.overrideWithValue(logger),
        biometricsServiceProvider.overrideWithValue(
          biometrics ?? _FakeBiometrics(),
        ),
        conn.authServiceProvider.overrideWithValue(
          AuthService(secure: secure, settings: repository, logger: logger),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConnectionSettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows editable connection fields with a seeded API key', (
    tester,
  ) async {
    await _pump(tester);

    final server = tester.widget<TextField>(
      find.byKey(const Key('connection-server')),
    );
    expect(server.controller!.text, 'https://photos.example.com');

    final apiKey = tester.widget<TextField>(
      find.byKey(const Key('connection-api-key')),
    );
    expect(apiKey.obscureText, isTrue);
    expect(apiKey.controller!.text, 'super-secret-key');

    expect(
      find.widgetWithText(FilledButton, 'Save connection'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('connection-test')), findsOneWidget);
    expect(find.text('Manage albums'), findsNothing);
    expect(find.text('Reveal API key'), findsNothing);
    expect(find.text('Edit connection'), findsNothing);
  });

  testWidgets('eye icon reveals the API key', (tester) async {
    final biometrics = _FakeBiometrics();
    await _pump(tester, biometrics: biometrics);

    await tester.tap(find.byTooltip('Show API key'));
    await tester.pumpAndSettle();

    final apiKey = tester.widget<TextField>(
      find.byKey(const Key('connection-api-key')),
    );
    expect(apiKey.obscureText, isFalse);
    expect(find.byTooltip('Hide API key'), findsOneWidget);
    expect(biometrics.calls, 1);
    expect(biometrics.reason, 'Reveal API key');
  });

  testWidgets('denied authentication keeps the API key obscured', (
    tester,
  ) async {
    final biometrics = _FakeBiometrics(allow: false);
    await _pump(tester, biometrics: biometrics);

    await tester.tap(find.byTooltip('Show API key'));
    await tester.pumpAndSettle();

    final apiKey = tester.widget<TextField>(
      find.byKey(const Key('connection-api-key')),
    );
    expect(apiKey.obscureText, isTrue);
    expect(biometrics.calls, 1);
  });

  testWidgets('copy icon authenticates and copies the API key', (tester) async {
    final biometrics = _FakeBiometrics();
    final clipboard = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        clipboard.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, biometrics: biometrics);

    await tester.tap(find.byKey(const Key('connection-copy-key')));
    await tester.pumpAndSettle();

    expect(biometrics.calls, 1);
    expect(biometrics.reason, 'Copy API key');
    expect(clipboard.any((call) => call.method == 'Clipboard.setData'), isTrue);
    expect(find.text('API key copied'), findsOneWidget);
  });
}
