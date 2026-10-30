import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/connection_providers.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/setup/permission_summary.dart';
import 'package:photoframe/l10n/app_localizations.dart';

/// Connects to an Immich server with an API key or OAuth.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _server = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  AuthMode _mode = AuthMode.apiKey;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _server.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final state = ref.read(connectionControllerProvider).value;
      final url = state?.settings.connection.serverUrl;
      if (url != null && url.isNotEmpty && _server.text.isEmpty) {
        _server.text = ImmichClient.displayUrl(url);
      }
    });
  }

  @override
  void dispose() {
    _server.removeListener(_refresh);
    _server.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _usesHttp {
    return _server.text.trim().toLowerCase().startsWith('http://');
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final controller = ref.read(connectionControllerProvider.notifier);
    final server = _server.text.trim();
    final report = _mode == AuthMode.oauth
        ? await controller.connectWithOAuth(server)
        : await controller.connectWithApiKey(server, _apiKey.text.trim());
    if (!mounted) {
      return;
    }
    if (report != null && report.canConnect && _mode == AuthMode.apiKey) {
      _apiKey.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final asyncState = ref.watch(connectionControllerProvider);
    final body = SafeArea(
      child: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load connection settings')),
        data: (state) => _buildForm(context, l, state),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.setup)),
      body: body,
    );
  }

  Widget _buildForm(
    BuildContext context,
    AppLocalizations l,
    ConnectionState state,
  ) {
    final theme = Theme.of(context);
    final busy = state.busy;
    final report = state.report;
    final failure = state.failure;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('setup-server-url'),
                  controller: _server,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l.serverUrl,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Enter a server URL';
                    }
                    if (!ImmichClient.isValidServerUrl(text)) {
                      return 'Enter a valid http(s) URL';
                    }
                    return null;
                  },
                ),
                if (_usesHttp) ...[
                  const SizedBox(height: 8),
                  Text(
                    'HTTP is not encrypted. HTTPS is recommended.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                SegmentedButton<AuthMode>(
                  segments: <ButtonSegment<AuthMode>>[
                    ButtonSegment<AuthMode>(
                      value: AuthMode.apiKey,
                      label: Text(l.apiKey),
                    ),
                    const ButtonSegment<AuthMode>(
                      value: AuthMode.oauth,
                      label: Text('OAuth'),
                    ),
                  ],
                  selected: <AuthMode>{_mode},
                  onSelectionChanged: busy
                      ? null
                      : (selection) {
                          setState(() {
                            _mode = selection.first;
                            _apiKey.clear();
                          });
                        },
                ),
                const SizedBox(height: 16),
                if (_mode == AuthMode.apiKey) ...[
                  TextFormField(
                    key: const Key('setup-api-key'),
                    controller: _apiKey,
                    enabled: !busy,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: l.apiKey,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscure = !_obscure;
                          });
                        },
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        tooltip: _obscure ? l.show : l.hide,
                      ),
                    ),
                    validator: (value) {
                      if (_mode != AuthMode.apiKey) {
                        return null;
                      }
                      if ((value?.trim() ?? '').isEmpty) {
                        return 'Enter an API key';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('setup-connect'),
                    onPressed: busy ? null : _connect,
                    child: Text(l.connect),
                  ),
                ] else ...[
                  Text(
                    'Sign in through your browser, then return to Photo Frame.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('setup-oauth-signin'),
                    onPressed: busy ? null : _connect,
                    child: Text(l.signIn),
                  ),
                ],
                if (busy) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (failure != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        failure.message,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  if (failure.statusCode == 308 && _usesHttp) ...[
                    const SizedBox(height: 8),
                    Text('Try the https:// URL for this server.'),
                  ],
                ],
                if (report != null) ...[
                  const SizedBox(height: 24),
                  PermissionSummary(report: report),
                  const SizedBox(height: 16),
                  if (report.canConnect)
                    FilledButton(
                      key: const Key('setup-continue'),
                      onPressed: () => context.go('/albums'),
                      child: Text(l.continueLabel),
                    )
                  else
                    OutlinedButton(
                      key: const Key('setup-retry'),
                      onPressed: busy ? null : _connect,
                      child: Text(l.retry),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
