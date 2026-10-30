import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/settings/app_settings.dart';

class MediaFilter {
  const MediaFilter({this.selectedAssetIds = const <String>{}});

  final Set<String> selectedAssetIds;

  List<ImmichAsset> apply(List<ImmichAsset> assets) {
    if (selectedAssetIds.isEmpty) {
      return assets;
    }
    return assets
        .where((asset) => selectedAssetIds.contains(asset.id))
        .toList();
  }
}

class CustomizationResolver {
  const CustomizationResolver({
    this.defaultProfile = const AspectProfile(),
    this.customizations = const <CustomizationProfile>[],
  });

  final AspectProfile defaultProfile;
  final List<CustomizationProfile> customizations;

  AspectProfile resolve(ImmichAsset? asset) {
    final kind = asset?.type;
    final aspect =
        aspectBucketFor(asset?.width, asset?.height) ?? asset?.aspectBucket;
    for (final customization in customizations) {
      if (customization.matches(kind, aspect)) {
        return customization.profile;
      }
    }
    return defaultProfile;
  }

  ImageFit effectiveFit(ImmichAsset? asset) {
    return resolve(asset).fit;
  }
}
