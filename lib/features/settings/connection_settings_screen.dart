import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:photoframe/app/connection_providers.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';
import 'package:photoframe/features/setup/permission_summary.dart';
import 'package:photoframe/l10n/app_localizations.dart';

/// Shows and edits the Immich server connection.
class ConnectionSettingsScreen extends ConsumerStatefulWidget {
  const ConnectionSettingsScreen({super.key});

  @override
  ConsumerState<ConnectionSettingsScreen> createState() =>
      _ConnectionSettingsScreenState();
}

class _ConnectionSettingsScreenState
    extends ConsumerState<ConnectionSettingsScreen> {
  final TextEditingController _server = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  bool _obscure = true;
  bool _seeded = false;

  @override
  void dispose() {
    _server.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final asyncState = ref.watch(connectionControllerProvider);
    return SettingsScaffold(
      title: l.connection,
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load connection settings')),
        data: (state) {
          _seed(state);
          return _body(context, state);
        },
      ),
    );
  }

  Future<void> _seed(ConnectionState state) async {
    if (_seeded) {
      return;
    }
    _seeded = true;
    _server.text = ImmichClient.displayUrl(state.settings.connection.serverUrl);
    final key = await ref.read(authServiceProvider).readApiKeyForReveal();
    if (!mounted || _apiKey.text.isNotEmpty) {
      return;
    }
    _apiKey.text = key ?? '';
  }

  Widget _body(BuildContext context, ConnectionState state) {
    final connection = state.settings.connection;
    final report = state.report;
    final busy = state.busy;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const Key('connection-server'),
          controller: _server,
          enabled: !busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('connection-api-key'),
          controller: _apiKey,
          enabled: !busy,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'API key',
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('connection-copy-key'),
                  tooltip: 'Copy API key',
                  icon: const Icon(Icons.copy),
                  onPressed: _copyApiKey,
                ),
                IconButton(
                  tooltip: _obscure ? 'Show API key' : 'Hide API key',
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: _toggleVisibility,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('connection-save'),
          onPressed: busy ? null : _save,
          child: Text(busy ? 'Saving...' : 'Save connection'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('connection-test'),
          onPressed: busy ? null : _testConnection,
          child: const Text('Test connection'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : _oauth,
          child: const Text('Sign in with OAuth'),
        ),
        if (state.isConnected) ...[
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('User'),
                  subtitle: Text(_userLabel(connection)),
                ),
                ListTile(
                  title: const Text('Auth mode'),
                  subtitle: Text(
                    connection.authMode == AuthMode.oauth ? 'OAuth' : 'API key',
                  ),
                ),
                ListTile(
                  title: const Text('Last connected'),
                  subtitle: Text(_formatDate(connection.lastConnectedAt)),
                ),
                ListTile(
                  title: const Text('Selected albums'),
                  subtitle: Text('${state.selectedAlbumIds.length}'),
                ),
              ],
            ),
          ),
          if (report != null) ...[
            const SettingsSectionHeader('API key permissions'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PermissionSummary(report: report),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: busy ? null : _disconnect,
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ],
    );
  }

  Future<void> _toggleVisibility() async {
    if (_obscure) {
      final allowed = await ref
          .read(biometricsServiceProvider)
          .authenticate('Reveal API key');
      if (!allowed || !mounted) {
        return;
      }
    }
    setState(() {
      _obscure = !_obscure;
    });
  }

  Future<void> _copyApiKey() async {
    final key = _apiKey.text;
    if (key.isEmpty) {
      return;
    }
    final allowed = await ref
        .read(biometricsServiceProvider)
        .authenticate('Copy API key');
    if (!allowed || !mounted) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: key));
    if (!mounted) {
      return;
    }
    _snack('API key copied');
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final server = _server.text.trim();
    final key = _apiKey.text.trim();
    if (!ImmichClient.isValidServerUrl(server)) {
      _snack('Enter a valid http(s) URL');
      return;
    }
    if (key.isEmpty) {
      _snack('Enter an API key');
      return;
    }
    final before = ref
        .read(connectionControllerProvider)
        .value
        ?.settings
        .connection;
    final report = await ref
        .read(connectionControllerProvider.notifier)
        .connectWithApiKey(server, key);
    if (!mounted) {
      return;
    }
    if (report == null || !report.canConnect) {
      _snack('Connection failed');
      return;
    }
    await _afterConnected(before);
    if (!mounted) {
      return;
    }
    final saved = ref
        .read(connectionControllerProvider)
        .value
        ?.settings
        .connection;
    _server.text = ImmichClient.displayUrl(saved?.serverUrl);
    _snack('Connection saved');
  }

  Future<void> _testConnection() async {
    final server = _server.text.trim();
    final key = _apiKey.text.trim();
    if (!ImmichClient.isValidServerUrl(server)) {
      _snack('Enter a valid http(s) URL');
      return;
    }
    if (key.isEmpty) {
      _snack('Enter an API key');
      return;
    }
    final report = await ref
        .read(connectionControllerProvider.notifier)
        .testConnectionWithApiKey(server, key);
    if (!mounted) {
      return;
    }
    _snack(report?.canConnect == true ? 'Connection OK' : 'Connection failed');
  }

  Future<void> _oauth() async {
    final server = _server.text.trim();
    if (!ImmichClient.isValidServerUrl(server)) {
      _snack('Enter a valid http(s) URL');
      return;
    }
    final before = ref
        .read(connectionControllerProvider)
        .value
        ?.settings
        .connection;
    final report = await ref
        .read(connectionControllerProvider.notifier)
        .connectWithOAuth(server);
    if (!mounted) {
      return;
    }
    if (report == null || !report.canConnect) {
      _snack('Connection failed');
      return;
    }
    await _afterConnected(before);
    if (!mounted) {
      return;
    }
    _snack('Connection saved');
  }

  Future<void> _afterConnected(ConnectionSettings? before) async {
    final after = ref
        .read(connectionControllerProvider)
        .value
        ?.settings
        .connection;
    if (_normalizedServer(before?.serverUrl) !=
            _normalizedServer(after?.serverUrl) ||
        before?.userId != after?.userId) {
      await ref.read(cacheStoreProvider).clear();
      await ref
          .read(connectionControllerProvider.notifier)
          .saveAlbumSelection(<String>{});
      await ref
          .read(settingsControllerProvider.notifier)
          .save(
            (current) => current.copyWith(
              filters: current.filters.copyWith(selectedAssetIds: <String>{}),
            ),
          );
    }
    await ref.read(settingsControllerProvider.notifier).reload();
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect from Immich?'),
        content: const Text(
          'The API key and saved connection will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(connectionControllerProvider.notifier).disconnect();
    if (!mounted) {
      return;
    }
    _server.clear();
    _apiKey.clear();
    setState(() {
      _obscure = true;
      _seeded = false;
    });
    _snack('Disconnected');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _userLabel(ConnectionSettings connection) {
    final name = (connection.userName ?? '').trim();
    final email = (connection.userEmail ?? '').trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name ($email)';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (email.isNotEmpty) {
      return email;
    }
    return 'Unknown user';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Never';
    }
    return DateFormat.yMMMd().add_jm().format(value.toLocal());
  }
}

String _normalizedServer(String? url) {
  var text = (url ?? '').trim().toLowerCase();
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('/api')) {
    text = text.substring(0, text.length - 4);
  }
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
