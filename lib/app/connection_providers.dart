import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/immich/auth_service.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/immich/oauth_service.dart';
import 'package:photoframe/data/secure/secure_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';

final Provider<AuthService> authServiceProvider = Provider<AuthService>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return AuthService(
    secure: bootstrap.secure,
    settings: bootstrap.settings,
    logger: bootstrap.logger,
  );
});

final Provider<OAuthService> oauthServiceProvider = Provider<OAuthService>(
  (ref) => OAuthService(),
);

final AsyncNotifierProvider<ConnectionController, ConnectionState>
connectionControllerProvider =
    AsyncNotifierProvider<ConnectionController, ConnectionState>(
      ConnectionController.new,
    );

class ConnectionState {
  const ConnectionState({
    required this.settings,
    this.report,
    this.albums = const <ImmichAlbum>[],
    this.busy = false,
    this.failure,
  });

  final AppSettings settings;
  final PermissionReport? report;
  final List<ImmichAlbum> albums;
  final bool busy;
  final AppFailure? failure;

  bool get isConnected {
    final connection = settings.connection;
    return (connection.serverUrl ?? '').isNotEmpty &&
        connection.permissions.isNotEmpty &&
        report?.canConnect != false;
  }

  Set<String> get selectedAlbumIds => settings.connection.albumIds;

  ConnectionState copyWith({
    AppSettings? settings,
    PermissionReport? report,
    List<ImmichAlbum>? albums,
    bool? busy,
    AppFailure? failure,
  }) {
    return ConnectionState(
      settings: settings ?? this.settings,
      report: report ?? this.report,
      albums: albums ?? this.albums,
      busy: busy ?? this.busy,
      failure: failure,
    );
  }
}

class ConnectionController extends AsyncNotifier<ConnectionState> {
  static const AppFailure _invalidUrl = AppFailure(
    FailureKind.invalidResponse,
    'Invalid server URL',
  );
  static const AppFailure _notConnected = AppFailure(
    FailureKind.auth,
    'Not connected',
  );
  static const AppFailure _failed = AppFailure(
    FailureKind.unknown,
    'Connection failed',
  );

  @override
  Future<ConnectionState> build() async {
    final settings = await ref.watch(settingsRepositoryProvider).load();
    return ConnectionState(
      settings: settings,
      report: _reportFromSettings(settings.connection),
    );
  }

  Future<PermissionReport?> connectWithApiKey(
    String serverUrl,
    String apiKey,
  ) async {
    final current = await _current();
    final trimmed = serverUrl.trim();
    if (!ImmichClient.isValidServerUrl(trimmed)) {
      _set(current.copyWith(failure: _invalidUrl));
      return null;
    }
    _set(current.copyWith(busy: true, failure: null));
    try {
      final report = await ref
          .read(authServiceProvider)
          .connectWithApiKey(
            serverBase: Uri.parse(trimmed),
            apiKey: apiKey.trim(),
          );
      return await _applyReport(report);
    } on AppFailure catch (failure) {
      _set(current.copyWith(busy: false, failure: failure));
      return null;
    } on Object {
      _set(current.copyWith(busy: false, failure: _failed));
      return null;
    }
  }

  Future<PermissionReport?> testConnectionWithApiKey(
    String serverUrl,
    String apiKey,
  ) async {
    final current = await _current();
    final trimmed = serverUrl.trim();
    if (!ImmichClient.isValidServerUrl(trimmed)) {
      _set(current.copyWith(failure: _invalidUrl));
      return null;
    }
    _set(current.copyWith(busy: true, failure: null));
    try {
      final report = await ref
          .read(authServiceProvider)
          .testApiKey(
            serverBase: Uri.parse(trimmed),
            apiKey: apiKey.trim(),
          );
      _set(
        current.copyWith(
          busy: false,
          failure: report.canConnect ? null : report.blockingFailure,
        ),
      );
      return report;
    } on AppFailure catch (failure) {
      _set(current.copyWith(busy: false, failure: failure));
      return null;
    } on Object {
      _set(current.copyWith(busy: false, failure: _failed));
      return null;
    }
  }

  Future<PermissionReport?> connectWithOAuth(String serverUrl) async {
    final current = await _current();
    final trimmed = serverUrl.trim();
    if (!ImmichClient.isValidServerUrl(trimmed)) {
      _set(current.copyWith(failure: _invalidUrl));
      return null;
    }
    _set(current.copyWith(busy: true, failure: null));
    try {
      final oauth = ref.read(oauthServiceProvider);
      final base = Uri.parse(trimmed);
      final session = Platform.isAndroid
          ? await oauth.runAndroid(
              serverBase: base,
              redirectScheme: Uri.parse(
                'com.rincew1nd.photoframe://oauth',
              ),
            )
          : await oauth.runDesktop(serverBase: base);
      final report = await ref
          .read(authServiceProvider)
          .connectWithOAuth(serverBase: base, session: session);
      return await _applyReport(report);
    } on AppFailure catch (failure) {
      _set(current.copyWith(busy: false, failure: failure));
      return null;
    } on Object {
      _set(current.copyWith(busy: false, failure: _failed));
      return null;
    }
  }

  Future<void> refreshAlbums() async {
    final current = await _current();
    _set(current.copyWith(busy: true, failure: null));
    try {
      final client = await clientFromStoredCredentials();
      final albums = await client.getAlbums();
      _set(current.copyWith(busy: false, albums: albums));
    } on AppFailure catch (failure) {
      _set(current.copyWith(busy: false, failure: failure));
    } on Object {
      _set(current.copyWith(busy: false, failure: _failed));
    }
  }

  Future<void> saveAlbumSelection(Set<String> albumIds) async {
    final repository = ref.read(settingsRepositoryProvider);
    final current = await _current();
    final settings = current.settings.copyWith(
      connection: current.settings.connection.copyWith(
        albumIds: Set<String>.from(albumIds),
      ),
    );
    await repository.save(settings);
    _set(current.copyWith(settings: settings));
    await _reloadSettingsController();
  }

  Future<void> recheckPermissions() async {
    final current = await _current();
    _set(current.copyWith(busy: true, failure: null));
    try {
      final report = await ref.read(authServiceProvider).recheckPermissions();
      final settings = await ref.read(settingsRepositoryProvider).load();
      _set(
        current.copyWith(
          busy: false,
          settings: settings,
          report: report ?? current.report,
          failure: report == null ? _notConnected : null,
        ),
      );
    } on AppFailure catch (failure) {
      _set(current.copyWith(busy: false, failure: failure));
    } on Object {
      _set(current.copyWith(busy: false, failure: _failed));
    }
  }

  Future<void> disconnect() async {
    await ref.read(authServiceProvider).disconnect();
    final settings = await ref.read(settingsRepositoryProvider).load();
    _set(
      ConnectionState(
        settings: settings,
        report: _reportFromSettings(settings.connection),
      ),
    );
    await _reloadSettingsController();
  }

  Future<ImmichClient> clientFromStoredCredentials() async {
    final settings = await ref.read(settingsRepositoryProvider).load();
    final serverUrl = settings.connection.serverUrl;
    final secure = ref.read(secureStoreProvider);
    final apiKey = await secure.read(SecretKeys.immichApiKey);
    final accessToken = await secure.read(SecretKeys.immichAccessToken);
    final hasApiKey = apiKey != null && apiKey.isNotEmpty;
    final hasToken = accessToken != null && accessToken.isNotEmpty;
    if (serverUrl == null || serverUrl.isEmpty || (!hasApiKey && !hasToken)) {
      throw _notConnected;
    }
    return ImmichClient(
      baseUri: Uri.parse(serverUrl),
      apiKey: hasApiKey ? apiKey : null,
      accessToken: hasToken ? accessToken : null,
    );
  }

  Future<ConnectionState> _current() async {
    final value = state.value;
    if (value != null) {
      return value;
    }
    final settings = await ref.read(settingsRepositoryProvider).load();
    return ConnectionState(
      settings: settings,
      report: _reportFromSettings(settings.connection),
    );
  }

  Future<PermissionReport> _applyReport(PermissionReport report) async {
    final settings = await ref.read(settingsRepositoryProvider).load();
    if (!report.canConnect) {
      _set(
        ConnectionState(
          settings: settings,
          report: report,
          failure: report.blockingFailure,
        ),
      );
      return report;
    }
    _set(
      ConnectionState(
        settings: settings,
        report: report,
        albums: await _fetchAlbums(),
      ),
    );
    await _reloadSettingsController();
    return report;
  }

  Future<List<ImmichAlbum>> _fetchAlbums() async {
    try {
      final client = await clientFromStoredCredentials();
      return await client.getAlbums();
    } on Object {
      return const <ImmichAlbum>[];
    }
  }

  Future<void> _reloadSettingsController() async {
    try {
      await ref.read(settingsControllerProvider.notifier).reload();
    } on Object {
      return;
    }
  }

  void _set(ConnectionState value) {
    state = AsyncData(value);
  }
}

PermissionReport? _reportFromSettings(ConnectionSettings connection) {
  if (connection.permissions.isEmpty) {
    return null;
  }
  return PermissionReport(
    permissions: <ImmichPermission, PermissionStatus>{
      for (final permission in ImmichPermission.values)
        permission: PermissionStatus.fromJson(
          connection.permissions[permission.jsonName],
        ),
    },
    checkedAt:
        connection.lastConnectedAt ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}
