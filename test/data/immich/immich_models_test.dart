import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/settings/app_settings.dart';

void main() {
  test('parses a full asset with exif and dimensions', () {
    final asset = ImmichAsset.fromJson(<String, dynamic>{
      'id': 'asset-1',
      'type': 'IMAGE',
      'originalMimeType': 'image/jpeg',
      'originalFileName': 'photo.jpg',
      'fileCreatedAt': '2024-01-01T10:00:00.000Z',
      'localDateTime': '2024-01-01T11:00:00',
      'exifInfo': <String, dynamic>{
        'exifImageWidth': 4000,
        'exifImageHeight': 3000,
        'dateTimeOriginal': '2024-01-01T09:00:00.000Z',
        'description': 'A photo',
        'city': 'Testville',
        'state': 'TestState',
        'country': 'Testland',
        'latitude': 10.5,
        'longitude': 20.5,
        'make': 'TestMake',
        'model': 'TestModel',
        'lensModel': 'TestLens',
        'fileSizeInByte': 2048,
      },
      'checksum': 'checksum',
      'thumbhash': 'thumbhash',
    });

    expect(asset.id, 'asset-1');
    expect(asset.type, MediaKind.photo);
    expect(asset.width, 4000);
    expect(asset.height, 3000);
    expect(asset.aspectBucket, AspectBucket.fourThree);
    expect(asset.fileCreatedAt, isNotNull);
    expect(asset.localDateTime, isNotNull);
    expect(asset.exif?.city, 'Testville');
    expect(asset.exif?.latitude, 10.5);
    expect(asset.exif?.fileSizeInByte, 2048);
    expect(asset.checksum, 'checksum');
    expect(asset.thumbhash, 'thumbhash');
  });

  test('tolerates missing exif and missing dimensions', () {
    final asset = ImmichAsset.fromJson(<String, dynamic>{
      'id': 'asset-2',
      'type': 'IMAGE',
      'livePhotoVideoId': 'live-1',
    });

    expect(asset.type, MediaKind.livePhoto);
    expect(asset.width, isNull);
    expect(asset.height, isNull);
    expect(asset.aspectBucket, isNull);
    expect(asset.fileCreatedAt, isNull);
    expect(asset.exif?.make, isNull);
  });

  test('maps video and mime types', () {
    final video = ImmichAsset.fromJson(<String, dynamic>{
      'id': 'video-1',
      'type': 'VIDEO',
      'duration': 5000,
      'exifInfo': <String, dynamic>{
        'exifImageWidth': 1920,
        'exifImageHeight': 1080,
      },
    });
    expect(video.type, MediaKind.video);
    expect(video.duration, 5000);
    expect(video.aspectBucket, AspectBucket.sixteenNine);

    final heic = ImmichAsset.fromJson(<String, dynamic>{
      'id': 'image-1',
      'originalMimeType': 'image/heic',
    });
    expect(heic.type, MediaKind.photo);

    final mimeVideo = ImmichAsset.fromJson(<String, dynamic>{
      'id': 'video-2',
      'originalMimeType': 'video/mp4',
    });
    expect(mimeVideo.type, MediaKind.video);
  });

  test('buckets aspect ratios at boundaries and ignores orientation', () {
    expect(aspectBucketFor(114, 100), AspectBucket.oneToOne);
    expect(aspectBucketFor(115, 100), AspectBucket.fourThree);
    expect(aspectBucketFor(142, 100), AspectBucket.threeTwo);
    expect(aspectBucketFor(164, 100), AspectBucket.sixteenNine);
    expect(aspectBucketFor(199, 100), AspectBucket.sixteenNine);
    expect(aspectBucketFor(200, 100), AspectBucket.panorama);

    expect(aspectBucketFor(100, 115), AspectBucket.fourThree);
    expect(aspectBucketFor(100, 200), AspectBucket.panorama);
    expect(aspectBucketFor(0, 100), isNull);
    expect(aspectBucketFor(-1, 100), isNull);
    expect(aspectBucketFor(null, 100), isNull);
  });

  test('classifies live photo dimensions inside the named tolerance', () {
    expect(aspectBucketFor(1280, 1708), AspectBucket.fourThree);
    expect(aspectBucketFor(1708, 1280), AspectBucket.fourThree);
    expect(aspectBucketFor(105, 100), AspectBucket.oneToOne);
    expect(aspectBucketFor(140, 100), AspectBucket.fourThree);
  });

  test('parses albums and versions tolerantly', () {
    final album = ImmichAlbum.fromJson(<String, dynamic>{
      'id': 'album-1',
      'albumName': 'Family',
      'assetCount': 3,
      'createdAt': '2024-01-01T09:00:00.000Z',
      'updatedAt': '2024-01-04T09:00:00.000Z',
      'albumThumbnailAssetId': 'asset-1',
      'shared': false,
      'hasSharedLink': true,
      'startDate': '2024-01-01T00:00:00.000Z',
      'endDate': '2024-01-03T00:00:00.000Z',
    });
    expect(album.albumName, 'Family');
    expect(album.assetCount, 3);
    expect(album.createdAt, isNotNull);
    expect(album.albumThumbnailAssetId, 'asset-1');
    expect(album.hasSharedLink, isTrue);

    final missing = ImmichAlbum.fromJson(<String, dynamic>{});
    expect(missing.id, '');
    expect(missing.albumName, '');
    expect(missing.assetCount, 0);
    expect(missing.createdAt, isNull);

    final version = ImmichServerVersion.fromJson(<String, dynamic>{
      'major': 3,
      'minor': '3',
      'patch': 5,
    });
    expect(version.major, 3);
    expect(version.minor, 3);
    expect(version.patch, 5);
    expect(version.toString(), '3.3.5');
  });

  test('permission report roundtrips without secrets', () {
    final report = PermissionReport(
      permissions: const <ImmichPermission, PermissionStatus>{
        ImmichPermission.userRead: PermissionStatus.granted,
        ImmichPermission.albumRead: PermissionStatus.granted,
        ImmichPermission.assetRead: PermissionStatus.granted,
        ImmichPermission.assetView: PermissionStatus.granted,
        ImmichPermission.assetDownload: PermissionStatus.denied,
      },
      blockingFailure: const AppFailure(
        FailureKind.permission,
        'Permission denied',
        statusCode: 403,
      ),
      checkedAt: DateTime.utc(2024, 1, 1),
      user: const ImmichUser(
        id: 'user-1',
        email: 'test@example.com',
        name: 'Test User',
      ),
    );

    final json = report.toJson();
    expect(json.containsKey('apiKey'), isFalse);
    expect(json.containsKey('accessToken'), isFalse);

    final restored = PermissionReport.fromJson(json);
    expect(restored.statusOf(ImmichPermission.userRead), PermissionStatus.granted);
    expect(restored.statusOf(ImmichPermission.assetDownload), PermissionStatus.denied);
    expect(restored.blockingFailure?.kind, FailureKind.permission);
    expect(restored.checkedAt, DateTime.utc(2024, 1, 1));
    expect(restored.user?.id, 'user-1');
    expect(restored.canConnect, isTrue);
    expect(restored.downloadAllowed, isFalse);
  });
}
