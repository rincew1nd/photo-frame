import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/connection_providers.dart' as conn;
import 'package:photoframe/app/router.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/slideshow/slideshow_screen.dart';
import 'package:photoframe/l10n/app_localizations.dart';

class _FakeConnectionController extends conn.ConnectionController {
  _FakeConnectionController(this.initial);

  final conn.ConnectionState initial;
  int saveCalls = 0;
  int refreshCalls = 0;
  Set<String>? saved;

  @override
  Future<conn.ConnectionState> build() async => initial;

  @override
  Future<void> refreshAlbums() async {
    refreshCalls++;
  }

  @override
  Future<void> saveAlbumSelection(Set<String> albumIds) async {
    saveCalls++;
    saved = Set<String>.from(albumIds);
  }
}

PermissionReport _report() {
  return PermissionReport(
    permissions: <ImmichPermission, PermissionStatus>{
      for (final permission in ImmichPermission.values)
        permission: PermissionStatus.granted,
    },
    checkedAt: DateTime.utc(2026, 1, 1),
  );
}

conn.ConnectionState _state() {
  final report = _report();
  return conn.ConnectionState(
    settings: AppSettings(
      connection: ConnectionSettings(
        serverUrl: 'https://photos.example.com/api',
        permissions: <String, String>{
          for (final entry in report.permissions.entries)
            entry.key.jsonName: entry.value.name,
        },
        albumIds: const <String>{'album-1'},
        lastConnectedAt: report.checkedAt,
      ),
    ),
    report: report,
    albums: const <ImmichAlbum>[
      ImmichAlbum(id: 'album-1', albumName: 'Trips', assetCount: 42),
      ImmichAlbum(id: 'album-2', albumName: 'Family', assetCount: 7),
    ],
  );
}

Future<_FakeConnectionController> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  late _FakeConnectionController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conn.connectionControllerProvider.overrideWith(() {
          controller = _FakeConnectionController(_state());
          return controller;
        }),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: createAppRouter(initialLocation: '/albums'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('lists albums with counts and toggles selection', (tester) async {
    final controller = await _pump(tester);

    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('42 assets'), findsOneWidget);
    expect(find.text('7 assets'), findsOneWidget);
    expect(controller.refreshCalls, 0);

    final trips = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Trips'),
    );
    final family = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Family'),
    );
    expect(trips.value, isTrue);
    expect(family.value, isFalse);

    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Family'),
          )
          .value,
      isTrue,
    );
    expect(controller.saveCalls, 0);
  });

  testWidgets('saves the selection and shows a snackbar', (tester) async {
    final controller = await _pump(tester);

    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save selection'));
    await tester.pumpAndSettle();

    expect(controller.saveCalls, 1);
    expect(controller.saved, <String>{'album-1', 'album-2'});
    expect(find.text('Album selection saved'), findsOneWidget);
  });

  testWidgets('continue saves and navigates to the slideshow', (tester) async {
    final controller = await _pump(tester);

    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(controller.saveCalls, 1);
    expect(controller.saved, <String>{'album-1', 'album-2'});
    expect(find.byType(SlideshowScreen), findsOneWidget);
  });
}
