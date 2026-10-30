import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';
import 'package:photoframe/features/slideshow/slideshow_controller.dart';

class CacheSettingsScreen extends ConsumerStatefulWidget {
  const CacheSettingsScreen({super.key});

  @override
  ConsumerState<CacheSettingsScreen> createState() =>
      _CacheSettingsScreenState();
}

class _CacheSettingsScreenState extends ConsumerState<CacheSettingsScreen> {
  Future<CacheStats>? _statsFuture;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _statsFuture = ref.read(cacheStoreProvider).stats();
  }

  @override
  Widget build(BuildContext context) {
    final asyncSettings = ref.watch(settingsControllerProvider);
    return SettingsScaffold(
      title: 'Cache',
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load settings')),
        data: _body,
      ),
    );
  }

  Widget _body(AppSettings settings) {
    final cache = settings.cache;
    return ListView(
      children: <Widget>[
        const SettingsSectionHeader('Storage limit'),
        _StorageLimitControl(
          quotaBytes: cache.quotaBytes,
          onChanged: (bytes) => _saveCache(
            (current) => current.copyWith(quotaBytes: bytes),
          ),
        ),
        const SettingsSectionHeader('Prefetch ahead'),
        ListTile(title: Text('${cache.prefetchCount} items')),
        Slider(
          value: cache.prefetchCount.clamp(0, 20).toDouble(),
          min: 0,
          max: 20,
          divisions: 20,
          label: '${cache.prefetchCount} items',
          onChanged: (value) => _saveCache(
            (current) => current.copyWith(prefetchCount: value.round()),
          ),
        ),
        const SettingsSectionHeader('Cached media'),
        FutureBuilder<CacheStats>(
          future: _statsFuture,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            if (stats == null) {
              return ListTile(
                title: Text(
                  snapshot.hasError
                      ? 'Unable to load statistics'
                      : 'Loading statistics...',
                ),
              );
            }
            return Column(
              children: <Widget>[
                ListTile(
                  title: const Text('Images'),
                  trailing: Text(
                    '${stats.imageCount} · ${_formatBytes(stats.imageBytes)}',
                  ),
                ),
                ListTile(
                  title: const Text('Videos'),
                  trailing: Text(
                    '${stats.videoCount} · ${_formatBytes(stats.videoBytes)}',
                  ),
                ),
                ListTile(
                  title: const Text('Total'),
                  trailing: Text(
                    '${stats.assetCount} assets · '
                    '${_formatBytes(stats.totalBytes)}',
                  ),
                ),
                ListTile(
                  title: const Text('Last sync'),
                  subtitle: Text(
                    stats.lastSync == null
                        ? 'Never synced'
                        : _formatDateTime(stats.lastSync!),
                  ),
                ),
              ],
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: FilledButton(
            onPressed: _syncing ? null : _sync,
            child: Text(_syncing ? 'Syncing...' : 'Sync now'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: TextButton(
            onPressed: _clear,
            child: const Text('Clear cache'),
          ),
        ),
      ],
    );
  }

  void _saveCache(CacheSettings Function(CacheSettings) update) {
    ref
        .read(settingsControllerProvider.notifier)
        .save((current) => current.copyWith(cache: update(current.cache)));
  }

  Future<void> _sync() async {
    if (_syncing) {
      return;
    }
    setState(() => _syncing = true);
    try {
      await ref.read(slideshowControllerProvider.notifier).syncNow();
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _statsFuture = ref.read(cacheStoreProvider).stats();
        });
      }
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text(
          'All cached media will be removed from this device.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(cacheStoreProvider).clear();
    if (!mounted) {
      return;
    }
    setState(() {
      _statsFuture = ref.read(cacheStoreProvider).stats();
    });
  }
}

class _StorageLimitControl extends StatefulWidget {
  const _StorageLimitControl({
    required this.quotaBytes,
    required this.onChanged,
  });

  final int quotaBytes;
  final ValueChanged<int> onChanged;

  @override
  State<_StorageLimitControl> createState() => _StorageLimitControlState();
}

class _StorageLimitControlState extends State<_StorageLimitControl> {
  static const List<int> _presetsMb = <int>[
    256,
    512,
    1024,
    2048,
    4096,
    8192,
    16384,
    32768,
    65536,
  ];
  static const int _minMb = 64;
  static const int _maxMb = 102400;
  static const int _bytesPerMb = 1024 * 1024;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _error;

  int _currentMb() => (widget.quotaBytes / _bytesPerMb).round();

  @override
  void initState() {
    super.initState();
    _controller.text = '${_currentMb()}';
  }

  @override
  void didUpdateWidget(_StorageLimitControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quotaBytes != widget.quotaBytes && !_focusNode.hasFocus) {
      _setText(_currentMb());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int get _presetIndex {
    final mb = _currentMb();
    var index = 0;
    for (var i = 1; i < _presetsMb.length; i++) {
      if ((_presetsMb[i] - mb).abs() < (_presetsMb[index] - mb).abs()) {
        index = i;
      }
    }
    return index;
  }

  void _setText(int mb) {
    final text = '$mb';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _applySlider(double value) {
    final mb = _presetsMb[value.round()];
    if (!_focusNode.hasFocus) {
      _setText(mb);
    }
    if (_error != null) {
      setState(() => _error = null);
    }
    widget.onChanged(mb * _bytesPerMb);
  }

  void _submit(String value) {
    final mb = int.tryParse(value.trim());
    if (mb == null || mb < _minMb || mb > _maxMb) {
      setState(() => _error = 'Enter $_minMb–$_maxMb MB');
      return;
    }
    if (_error != null) {
      setState(() => _error = null);
    }
    widget.onChanged(mb * _bytesPerMb);
  }

  @override
  Widget build(BuildContext context) {
    final index = _presetIndex;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: 'Custom limit',
              suffixText: 'MB',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: _submit,
          ),
        ),
        Slider(
          value: index.toDouble(),
          min: 0,
          max: (_presetsMb.length - 1).toDouble(),
          divisions: _presetsMb.length - 1,
          label: _formatLimit(_presetsMb[index]),
          onChanged: _applySlider,
        ),
      ],
    );
  }
}

String _formatLimit(int mb) {
  return mb >= 1024 ? '${mb ~/ 1024} GB' : '$mb MB';
}

String _formatBytes(int bytes) {
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
