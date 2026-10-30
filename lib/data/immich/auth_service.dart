import 'package:photoframe/core/clock.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/secure/secure_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';

/// Connects to Immich and persists the resulting credentials and settings.
class AuthService {
  AuthService({
    required SecureStore secure,
    required SettingsRepository settings,
    required AppLogger logger,
    Clock? clock,
  }) : _secure = secure,
       _settings = settings,
       _logger = logger,
       _clock = clock ?? const SystemClock();

  final SecureStore _secure;
  final SettingsRepository _settings;
  final AppLogger _logger;
  final Clock _clock;

  Future<PermissionReport> connectWithApiKey({
    required Uri serverBase,
    required String apiKey,
    String? userId,
    String? userEmail,
    String? userName,
  }) async {
    final base = _normalize(serverBase);
    if (base == null) {
      return _invalidUrlReport();
    }

    final client = ImmichClient(baseUri: base, apiKey: apiKey);
    final report = await client.checkPermissions();
    if (!report.canConnect) {
      return report;
    }

    await _storeApiKey(apiKey);
    await _saveConnection(
      base: base,
      authMode: AuthMode.apiKey,
      report: report,
      userId: userId,
      userEmail: userEmail,
      userName: userName,
    );
    return report;
  }

  Future<PermissionReport> testApiKey({
    required Uri serverBase,
    required String apiKey,
  }) async {
    final base = _normalize(serverBase);
    if (base == null) {
      return _invalidUrlReport();
    }

    final client = ImmichClient(baseUri: base, apiKey: apiKey);
    return client.checkPermissions();
  }

  Future<PermissionReport> connectWithOAuth({
    required Uri serverBase,
    required ImmichAuthSession session,
    String? userId,
    String? userEmail,
    String? userName,
  }) async {
    final base = _normalize(serverBase);
    if (base == null) {
      return _invalidUrlReport();
    }

    final client = ImmichClient(
      baseUri: base,
      apiKey: session.apiKey,
      accessToken: session.accessToken,
    );
    final report = await client.checkPermissions();
    if (!report.canConnect) {
      return report;
    }

    final apiKey = session.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      await _storeApiKey(apiKey);
    } else {
      await _storeAccessToken(session.accessToken);
    }

    await _saveConnection(
      base: base,
      authMode: AuthMode.oauth,
      report: report,
      userId: userId,
      userEmail: userEmail,
      userName: userName,
    );
    return report;
  }

  Future<void> disconnect() async {
    await _secure.delete(SecretKeys.immichApiKey);
    await _secure.delete(SecretKeys.immichAccessToken);
    await _secure.delete(SecretKeys.oauthVerifier);
    final current = await _settings.load();
    await _settings.save(
      current.copyWith(connection: const ConnectionSettings()),
    );
  }

  Future<PermissionReport?> recheckPermissions() async {
    final current = await _settings.load();
    final serverUrl = current.connection.serverUrl;
    if (serverUrl == null || serverUrl.isEmpty) {
      return null;
    }
    final base = _normalize(Uri.tryParse(serverUrl) ?? Uri());
    if (base == null) {
      return null;
    }

    final apiKey = await _secure.read(SecretKeys.immichApiKey);
    final accessToken = await _secure.read(SecretKeys.immichAccessToken);
    if ((apiKey == null || apiKey.isEmpty) &&
        (accessToken == null || accessToken.isEmpty)) {
      return null;
    }

    final client = ImmichClient(
      baseUri: base,
      apiKey: apiKey,
      accessToken: accessToken,
    );
    return client.checkPermissions();
  }

  Future<String?> readApiKeyForReveal() {
    return _secure.read(SecretKeys.immichApiKey);
  }

  Uri? _normalize(Uri serverBase) {
    try {
      return ImmichClient.normalizeBaseUrl(serverBase.toString());
    } on FormatException {
      return null;
    }
  }

  Future<void> _storeApiKey(String apiKey) async {
    await _secure.write(SecretKeys.immichApiKey, apiKey);
    await _secure.delete(SecretKeys.immichAccessToken);
    _logger.registerSecret(apiKey);
  }

  Future<void> _storeAccessToken(String? accessToken) async {
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }
    await _secure.write(SecretKeys.immichAccessToken, accessToken);
    await _secure.delete(SecretKeys.immichApiKey);
    _logger.registerSecret(accessToken);
  }

  Future<void> _saveConnection({
    required Uri base,
    required AuthMode authMode,
    required PermissionReport report,
    String? userId,
    String? userEmail,
    String? userName,
  }) async {
    final current = await _settings.load();
    final existing = current.connection;
    final connection = ConnectionSettings(
      serverUrl: base.toString(),
      authMode: authMode,
      userId: userId ?? report.user?.id ?? existing.userId,
      userEmail: userEmail ?? report.user?.email ?? existing.userEmail,
      userName: userName ?? report.user?.name ?? existing.userName,
      permissions: <String, String>{
        for (final entry in report.permissions.entries)
          entry.key.jsonName: entry.value.name,
      },
      albumIds: existing.albumIds,
      lastConnectedAt: _clock.now(),
    );
    await _settings.save(current.copyWith(connection: connection));
  }

  PermissionReport _invalidUrlReport() {
    return PermissionReport(
      permissions: <ImmichPermission, PermissionStatus>{
        for (final permission in ImmichPermission.values)
          permission: PermissionStatus.error,
      },
      blockingFailure: const AppFailure(
        FailureKind.invalidResponse,
        'Invalid server URL',
      ),
      checkedAt: _clock.now(),
    );
  }
}
