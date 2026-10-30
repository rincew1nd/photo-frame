import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/domain/media/media_filters.dart';

void main() {
  const photo16 = ImmichAsset(
    id: 'photo-16',
    type: MediaKind.photo,
    aspectBucket: AspectBucket.sixteenNine,
  );
  const live16 = ImmichAsset(
    id: 'live-16',
    type: MediaKind.livePhoto,
    aspectBucket: AspectBucket.sixteenNine,
  );
  const video16 = ImmichAsset(
    id: 'video-16',
    type: MediaKind.video,
    aspectBucket: AspectBucket.sixteenNine,
  );

  test('no selection keeps all assets', () {
    const filter = MediaFilter();

    final result = filter.apply(<ImmichAsset>[photo16, live16, video16]);

    expect(result.map((asset) => asset.id), <String>[
      'photo-16',
      'live-16',
      'video-16',
    ]);
  });

  test('selected ids keep only matches in input order', () {
    const filter = MediaFilter(
      selectedAssetIds: <String>{'video-16', 'photo-16'},
    );

    final result = filter.apply(<ImmichAsset>[photo16, live16, video16]);

    expect(result.map((asset) => asset.id), <String>['photo-16', 'video-16']);
  });

  test('empty asset list yields empty result', () {
    const filter = MediaFilter(selectedAssetIds: <String>{'photo-16'});

    expect(filter.apply(<ImmichAsset>[]), isEmpty);
  });

  test('empty customization conditions match anything', () {
    const customization = CustomizationProfile();

    expect(customization.matches(null, null), isTrue);
    expect(customization.matches(MediaKind.video, AspectBucket.panorama), isTrue);
    expect(customization.matches(MediaKind.photo, null), isTrue);
  });

  test('customization matches media types', () {
    const photos = CustomizationProfile(
      mediaTypes: <MediaKind>{MediaKind.photo},
    );
    const videos = CustomizationProfile(
      mediaTypes: <MediaKind>{MediaKind.video},
    );
    const livePhotos = CustomizationProfile(
      mediaTypes: <MediaKind>{MediaKind.livePhoto},
    );

    expect(photos.matches(MediaKind.photo, null), isTrue);
    expect(photos.matches(MediaKind.video, null), isFalse);
    expect(photos.matches(null, null), isFalse);
    expect(videos.matches(MediaKind.video, null), isTrue);
    expect(videos.matches(MediaKind.photo, null), isFalse);
    expect(livePhotos.matches(MediaKind.livePhoto, null), isTrue);
    expect(livePhotos.matches(MediaKind.photo, null), isFalse);
  });

  test('customization matches aspects', () {
    const wide = CustomizationProfile(
      aspects: <AspectBucket>{AspectBucket.sixteenNine},
    );

    expect(wide.matches(null, AspectBucket.sixteenNine), isTrue);
    expect(wide.matches(MediaKind.photo, AspectBucket.oneToOne), isFalse);
    expect(wide.matches(MediaKind.photo, null), isFalse);
  });

  test('customization Other matches a null aspect', () {
    const other = CustomizationProfile(
      aspects: <AspectBucket>{AspectBucket.other},
    );

    expect(other.matches(null, null), isTrue);
    expect(other.matches(MediaKind.photo, AspectBucket.other), isTrue);
    expect(other.matches(MediaKind.photo, AspectBucket.sixteenNine), isFalse);
  });

  test('customization resolver uses the first match and falls back', () {
    const defaultProfile = AspectProfile(fit: ImageFit.contain);
    const wideVideo = AspectProfile(fit: ImageFit.cover);
    const anyPhoto = AspectProfile(panStrength: 10);
    const catchAll = AspectProfile(fit: ImageFit.cover, panStrength: 50);
    const resolver = CustomizationResolver(
      defaultProfile: defaultProfile,
      customizations: <CustomizationProfile>[
        CustomizationProfile(
          id: 'wide-video',
          mediaTypes: <MediaKind>{MediaKind.video},
          aspects: <AspectBucket>{AspectBucket.sixteenNine},
          profile: wideVideo,
        ),
        CustomizationProfile(
          id: 'photos',
          mediaTypes: <MediaKind>{MediaKind.photo},
          profile: anyPhoto,
        ),
        CustomizationProfile(id: 'catch-all', profile: catchAll),
      ],
    );

    expect(resolver.resolve(video16), same(wideVideo));
    expect(resolver.resolve(photo16), same(anyPhoto));
    expect(resolver.resolve(live16), same(catchAll));
    expect(resolver.resolve(null), same(catchAll));

    const fallbackOnly = CustomizationResolver(defaultProfile: defaultProfile);
    expect(fallbackOnly.resolve(video16), same(defaultProfile));
  });

  test('customization resolver uses live dimensions over a stale bucket', () {
    const liveFourThree = AspectProfile(fit: ImageFit.cover);
    const resolver = CustomizationResolver(
      customizations: <CustomizationProfile>[
        CustomizationProfile(
          id: 'live-4-3',
          mediaTypes: <MediaKind>{MediaKind.livePhoto},
          aspects: <AspectBucket>{AspectBucket.fourThree},
          profile: liveFourThree,
        ),
      ],
    );
    const noBucket = ImmichAsset(
      id: 'live-43',
      type: MediaKind.livePhoto,
      exif: ImmichExif(width: 1280, height: 1708),
    );
    const staleBucket = ImmichAsset(
      id: 'live-43-stale',
      type: MediaKind.livePhoto,
      exif: ImmichExif(width: 1280, height: 1708),
      aspectBucket: AspectBucket.sixteenNine,
    );

    expect(resolver.resolve(noBucket), same(liveFourThree));
    expect(resolver.resolve(staleBucket), same(liveFourThree));
  });

  test('customization resolver falls back to the stored bucket', () {
    const liveFourThree = AspectProfile(fit: ImageFit.cover);
    const resolver = CustomizationResolver(
      customizations: <CustomizationProfile>[
        CustomizationProfile(
          id: 'live-4-3',
          mediaTypes: <MediaKind>{MediaKind.livePhoto},
          aspects: <AspectBucket>{AspectBucket.fourThree},
          profile: liveFourThree,
        ),
      ],
    );
    const storedBucket = ImmichAsset(
      id: 'live-stored',
      type: MediaKind.livePhoto,
      aspectBucket: AspectBucket.fourThree,
    );

    expect(resolver.resolve(storedBucket), same(liveFourThree));
  });

  test('customization resolver effective fit ignores pan strength', () {
    const containPan = AspectProfile(fit: ImageFit.contain, panStrength: 25);
    const stillProfile = AspectProfile(fit: ImageFit.contain);
    const coverPan = AspectProfile(fit: ImageFit.cover, panStrength: 25);
    const wideVideo = AspectProfile(fit: ImageFit.cover);

    expect(
      const CustomizationResolver(defaultProfile: containPan)
          .effectiveFit(photo16),
      ImageFit.contain,
    );
    expect(
      const CustomizationResolver(defaultProfile: stillProfile)
          .effectiveFit(photo16),
      ImageFit.contain,
    );
    expect(
      const CustomizationResolver(defaultProfile: coverPan)
          .effectiveFit(photo16),
      ImageFit.cover,
    );
    expect(
      const CustomizationResolver(
        customizations: <CustomizationProfile>[
          CustomizationProfile(
            mediaTypes: <MediaKind>{MediaKind.video},
            profile: wideVideo,
          ),
        ],
      ).effectiveFit(video16),
      ImageFit.cover,
    );
  });
}
