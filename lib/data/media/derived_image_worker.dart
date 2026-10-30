import 'dart:io';

import 'package:photoframe/data/media/derived_image_service.dart';
import 'package:photoframe/data/media/native/native_still_decoder.dart';
import 'package:photoframe/data/media/preview_only_decoder.dart';
import 'package:photoframe/data/media/still_decoder.dart';

class DerivedImageRequest {
  const DerivedImageRequest({
    required this.sourcePath,
    required this.assetId,
    required this.checksum,
    required this.targetLongSide,
    required this.derivedRootPath,
  });
  final String sourcePath;
  final String assetId;
  final String checksum;
  final int targetLongSide;
  final String derivedRootPath;
}

class DerivedImageResult {
  const DerivedImageResult({
    required this.path,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.cacheKey,
  });
  final String path;
  final int width;
  final int height;
  final int sizeBytes;
  final String cacheKey;
}

Future<DerivedImageResult?> deriveImageInBackground(
  DerivedImageRequest request,
) async {
  final StillDecoder decoder =
      NativeStillDecoder.tryCreate() ?? const PreviewOnlyStillDecoder();
  final service = DerivedImageService(
    decoder: decoder,
    derivedRoot: Directory(request.derivedRootPath),
  );
  final result = await service.ensure(
    source: File(request.sourcePath),
    assetId: request.assetId,
    checksum: request.checksum,
    targetLongSide: request.targetLongSide,
  );
  if (result == null) return null;
  return DerivedImageResult(
    path: result.file.path,
    width: result.width,
    height: result.height,
    sizeBytes: result.sizeBytes,
    cacheKey: result.cacheKey,
  );
}
