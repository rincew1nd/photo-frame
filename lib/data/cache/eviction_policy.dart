import 'package:photoframe/data/cache/cache_assets.dart';

class EvictionSelection {
  const EvictionSelection({
    this.evicted = const <CachedAsset>[],
    this.freedBytes = 0,
  });

  final List<CachedAsset> evicted;
  final int freedBytes;

  static EvictionSelection select({
    required List<CachedAsset> assets,
    required int quotaBytes,
    required int incomingBytes,
    required Set<String> protectedIds,
  }) {
    final existingBytes = assets.fold<int>(
      0,
      (total, asset) => total + asset.totalSizeBytes,
    );
    final overflow = existingBytes + incomingBytes - quotaBytes;
    if (overflow <= 0) {
      return const EvictionSelection();
    }

    final candidates =
        assets.where((asset) => !protectedIds.contains(asset.id)).toList()
          ..sort(
            (left, right) =>
                left.lastAccessedAt.compareTo(right.lastAccessedAt),
          );

    final evicted = <CachedAsset>[];
    var freedBytes = 0;
    for (final asset in candidates) {
      if (freedBytes >= overflow) {
        break;
      }
      evicted.add(asset);
      freedBytes += asset.totalSizeBytes;
    }

    return EvictionSelection(evicted: evicted, freedBytes: freedBytes);
  }
}
