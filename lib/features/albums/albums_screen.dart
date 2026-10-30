import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/connection_providers.dart';
import 'package:photoframe/l10n/app_localizations.dart';

class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  Set<String> _selected = <String>{};
  Set<String>? _syncedSelection;
  bool _autoRefreshTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _autoRefresh(ref.read(connectionControllerProvider).value);
    });
  }

  void _autoRefresh(ConnectionState? state) {
    if (_autoRefreshTriggered || state == null) {
      return;
    }
    if (!state.isConnected || state.albums.isNotEmpty) {
      return;
    }
    _autoRefreshTriggered = true;
    ref.read(connectionControllerProvider.notifier).refreshAlbums();
  }

  void _toggle(String albumId) {
    setState(() {
      if (_selected.contains(albumId)) {
        _selected.remove(albumId);
      } else {
        _selected.add(albumId);
      }
    });
  }

  Future<void> _save() async {
    await ref
        .read(connectionControllerProvider.notifier)
        .saveAlbumSelection(_selected);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Album selection saved')));
  }

  Future<void> _continue() async {
    await ref
        .read(connectionControllerProvider.notifier)
        .saveAlbumSelection(_selected);
    if (!mounted) {
      return;
    }
    context.go('/slideshow');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final asyncState = ref.watch(connectionControllerProvider);
    ref.listen(connectionControllerProvider, (previous, next) {
      _autoRefresh(next.value);
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(l.albums),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(connectionControllerProvider.notifier).refreshAlbums();
            },
          ),
          if (!context.canPop())
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
            ),
        ],
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _failure(
          'Unable to load albums',
          () => ref.invalidate(connectionControllerProvider),
        ),
        data: (state) {
          final selection = state.selectedAlbumIds;
          if (!identical(_syncedSelection, selection)) {
            _syncedSelection = selection;
            _selected = Set<String>.from(selection);
          }
          return _body(state);
        },
      ),
    );
  }

  Widget _body(ConnectionState state) {
    if (state.busy && state.albums.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.failure != null) {
      return _failure(state.failure!.message, () {
        ref.read(connectionControllerProvider.notifier).refreshAlbums();
      });
    }
    if (state.albums.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No albums found. Tap refresh to load your Immich albums.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: state.albums.length,
            itemBuilder: (context, index) {
              final album = state.albums[index];
              return CheckboxListTile(
                key: ValueKey<String>(album.id),
                title: Text(album.albumName),
                subtitle: Text('${album.assetCount} assets'),
                value: _selected.contains(album.id),
                onChanged: (value) => _toggle(album.id),
              );
            },
          ),
        ),
        _bottomBar(),
      ],
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selected.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'No albums selected, the slideshow will have no items.',
                  textAlign: TextAlign.center,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _save,
                    child: const Text('Save selection'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _continue,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _failure(String message, VoidCallback onRetry) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onRetry, child: Text(l.retry)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
