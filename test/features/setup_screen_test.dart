import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/connection_providers.dart' as conn;
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/setup/permission_summary.dart';
import 'package:photoframe/features/setup/setup_screen.dart';
import 'package:photoframe/l10n/app_localizations.dart';

class _FakeConnectionController extends conn.ConnectionController {
  _FakeConnectionController(this.initial);

  final conn.ConnectionState initial;

  @override
  Future<conn.ConnectionState> build() async => initial;

  @override
  Future<PermissionReport?> connectWithApiKey(
    String serverUrl,
    String apiKey,
  ) async => initial.report;

  @override
  Future<PermissionReport?> connectWithOAuth(String serverUrl) async =>
      initial.report;
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

conn.ConnectionState _state({
  PermissionReport? report,
  AppFailure? failure,
  bool busy = false,
  String? serverUrl,
}) {
  return conn.ConnectionState(
    settings: AppSettings(
      connection: ConnectionSettings(
        serverUrl: serverUrl,
        permissions: report == null
            ? const <String, String>{}
            : <String, String>{
                for (final entry in report.permissions.entries)
                  entry.key.jsonName: entry.value.name,
              },
        lastConnectedAt: report?.checkedAt,
      ),
    ),
    report: report,
    busy: busy,
    failure: failure,
  );
}

Future<void> _pump(
  WidgetTester tester,
  conn.ConnectionState state,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conn.connectionControllerProvider.overrideWith(
          () => _FakeConnectionController(state),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SetupScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows server URL and API key mode by default', (tester) async {
    await _pump(tester, _state());

    expect(find.text('Setup'), findsOneWidget);
    expect(find.byKey(const Key('setup-server-url')), findsOneWidget);
    expect(find.byKey(const Key('setup-api-key')), findsOneWidget);
    expect(find.byKey(const Key('setup-connect')), findsOneWidget);
    expect(find.byKey(const Key('setup-oauth-signin')), findsNothing);
  });

  testWidgets('switches to the OAuth tab', (tester) async {
    await _pump(tester, _state());

    await tester.tap(find.text('OAuth'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setup-oauth-signin')), findsOneWidget);
    expect(find.byKey(const Key('setup-api-key')), findsNothing);
  });

  testWidgets('validates the server URL before connecting', (tester) async {
    await _pump(tester, _state());

    await tester.enterText(
      find.byKey(const Key('setup-server-url')),
      'ftp://example.com',
    );
    await tester.tap(find.byKey(const Key('setup-connect')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid http(s) URL'), findsOneWidget);
  });

  testWidgets('shows the failure message in an error card', (tester) async {
    await _pump(
      tester,
      _state(
        failure: const AppFailure(FailureKind.network, 'Network unavailable'),
      ),
    );

    expect(find.text('Network unavailable'), findsOneWidget);
  });

  testWidgets('shows permission summary and continue after a successful state',
      (tester) async {
    final report = _grantedReport();
    await _pump(
      tester,
      _state(report: report, serverUrl: 'https://photos.example.com/api'),
    );

    expect(find.byType(PermissionSummary), findsOneWidget);
    expect(find.text('user.read'), findsOneWidget);
    expect(find.text('asset.download'), findsOneWidget);
    expect(find.text('Granted'), findsNWidgets(5));
    expect(find.byKey(const Key('setup-continue')), findsOneWidget);
    expect(find.byKey(const Key('setup-retry')), findsNothing);
  });

  testWidgets('shows retry when blocking permissions fail', (tester) async {
    final report = PermissionReport(
      permissions: <ImmichPermission, PermissionStatus>{
        for (final permission in ImmichPermission.values)
          permission: PermissionStatus.granted,
        ImmichPermission.albumRead: PermissionStatus.denied,
      },
      checkedAt: DateTime.utc(2026, 1, 1),
      blockingFailure: const AppFailure(
        FailureKind.permission,
        'Permission denied',
      ),
    );
    await _pump(
      tester,
      _state(report: report, failure: report.blockingFailure),
    );

    expect(find.byType(PermissionSummary), findsOneWidget);
    expect(find.byKey(const Key('setup-continue')), findsNothing);
    expect(find.byKey(const Key('setup-retry')), findsOneWidget);
  });
}
