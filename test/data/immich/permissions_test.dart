import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/immich/models.dart';

import '../../support/mock_immich_server.dart';

void main() {
  late MockImmichServer server;

  setUp(() async {
    server = await MockImmichServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  ImmichClient client() {
    return ImmichClient(baseUri: server.apiUrl, apiKey: 'test-key');
  }

  test('reports all five permissions granted', () async {
    final report = await client().checkPermissions();

    expect(report.statusOf(ImmichPermission.userRead), PermissionStatus.granted);
    expect(report.statusOf(ImmichPermission.albumRead), PermissionStatus.granted);
    expect(report.statusOf(ImmichPermission.assetRead), PermissionStatus.granted);
    expect(report.statusOf(ImmichPermission.assetView), PermissionStatus.granted);
    expect(
      report.statusOf(ImmichPermission.assetDownload),
      PermissionStatus.granted,
    );
    expect(report.canConnect, isTrue);
    expect(report.downloadAllowed, isTrue);
    expect(report.blockingFailure, isNull);
    expect(report.user?.id, 'user-1');
    expect(report.checkedAt, isNotNull);
  });

  test('degrades when download is denied', () async {
    server.denyDownload = true;

    final report = await client().checkPermissions();

    expect(
      report.statusOf(ImmichPermission.assetDownload),
      PermissionStatus.denied,
    );
    expect(report.downloadAllowed, isFalse);
    expect(report.canConnect, isTrue);
    expect(report.blockingFailure, isNull);
  });

  test('blocks when album access is denied', () async {
    server.denyAlbum = true;

    final report = await client().checkPermissions();

    expect(
      report.statusOf(ImmichPermission.albumRead),
      PermissionStatus.denied,
    );
    expect(report.canConnect, isFalse);
    expect(report.blockingFailure?.kind, FailureKind.permission);
    expect(report.statusOf(ImmichPermission.assetView), PermissionStatus.granted);
  });

  test('blocks on unauthorized responses', () async {
    server.unauthorized = true;

    final report = await client().checkPermissions();

    expect(report.statusOf(ImmichPermission.userRead), PermissionStatus.error);
    expect(report.canConnect, isFalse);
    expect(report.blockingFailure?.kind, FailureKind.auth);
  });

  test('leaves view and download untested when there are no assets', () async {
    server.emptyLibrary = true;

    final report = await client().checkPermissions();

    expect(report.statusOf(ImmichPermission.assetRead), PermissionStatus.granted);
    expect(
      report.statusOf(ImmichPermission.assetView),
      PermissionStatus.notTested,
    );
    expect(
      report.statusOf(ImmichPermission.assetDownload),
      PermissionStatus.notTested,
    );
    expect(report.canConnect, isTrue);
    expect(report.downloadAllowed, isFalse);
  });
}
