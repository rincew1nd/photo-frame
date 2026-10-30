import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/slideshow/slideshow_controller.dart';
import 'package:photoframe/platform/paths.dart';

/// Lets the viewer pick which cached assets appear in the slideshow.
class MediaSelectionScreen extends ConsumerStatefulWidget {
  const MediaSelectionScreen({super.key});

  @override
  ConsumerState<MediaSelectionScreen> createState() =>
      _MediaSelectionScreenState();
}

class _MediaSelectionScreenState extends ConsumerState<MediaSelectionScreen> {
  Set<String> _selected = <String>{};
  bool _initialized = false;
  bool? _unlocked;
  bool _authFailed = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final canAuthenticate = await ref
        .read(platformServicesProvider)
        .biometrics
        .canAuthenticate;
    if (!mounted) {
      return;
    }
    setState(() => _unlocked = !canAuthenticate);
  }

  Future<void> _authenticate() async {
    final ok = await ref
        .read(platformServicesProvider)
        .biometrics
        .authenticate('Unlock media selection');
    if (!mounted) {
      return;
    }
    if (ok) {
      setState(() => _unlocked = true);
    } else {
      setState(() => _authFailed = true);
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll(List<CachedAsset> assets) {
    setState(() {
      _selected = assets.map((asset) => asset.id).toSet();
    });
  }

  Future<void> _save() async {
    final selection = Set<String>.of(_selected);
    await ref
        .read(settingsControllerProvider.notifier)
        .save(
          (current) => current.copyWith(
            filters: current.filters.copyWith(selectedAssetIds: selection),
          ),
        );
    if (!mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/slideshow');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider).value;
    final asyncState = ref.watch(slideshowControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/slideshow'),
        ),
        title: const Text('Media selection'),
      ),
      body: _unlocked == null
          ? const Center(child: CircularProgressIndicator())
          : _unlocked == false
          ? _unlockCard()
          : _content(settings, asyncState),
    );
  }

  Widget _unlockCard() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 40),
                  const SizedBox(height: 12),
                  const Text('Media selection is locked'),
                  if (_authFailed) ...[
                    const SizedBox(height: 8),
                    const Text('Authentication cancelled'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/slideshow'),
                      child: const Text('Cancel'),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _authenticate,
                      child: const Text('Unlock'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(AppSettings? settings, AsyncValue<SlideshowViewState> async) {
    final state = async.value;
    if (settings == null || state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_initialized) {
      _selected = Set<String>.from(settings.filters.selectedAssetIds);
      _initialized = true;
    }
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  '${_selected.length} / ${state.cached.length} assets selected',
                ),
              ],
            ),
          ),
          Expanded(
            child: state.cached.isEmpty
                ? const Center(child: Text('No cached assets'))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: state.cached.length,
                    itemBuilder: (context, index) {
                      final asset = state.cached[index];
                      return GestureDetector(
                        key: ValueKey<String>(asset.id),
                        onTap: () => _toggle(asset.id),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _thumbnail(asset),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Checkbox(
                                value: _selected.contains(asset.id),
                                onChanged: (_) => _toggle(asset.id),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          _bottomBar(state.cached),
        ],
      ),
    );
  }

  Widget _thumbnail(CachedAsset asset) {
    final file = fileIfExists(asset.thumbnailPath);
    if (file == null) {
      return ColoredBox(
        color: Colors.black12,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }
    return Image.file(file, fit: BoxFit.cover);
  }

  Widget _bottomBar(List<CachedAsset> assets) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _selectAll(assets),
              child: const Text('Select all'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => setState(_selected.clear),
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
