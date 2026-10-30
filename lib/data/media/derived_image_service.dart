import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photoframe/data/media/still_decoder.dart';
import 'package:photoframe/platform/paths.dart';

const int _bucketStep = 320;
const int _minBucket = 320;
const int _maxBucket = 3840;
const int _jpegQuality = 85;

class DerivedImage {
  const DerivedImage({
    required this.file,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.cacheKey,
  });
  final File file;
  final int width;
  final int height;
  final int sizeBytes;
  final String cacheKey;
}

class DerivedImageService {
  DerivedImageService({
    required StillDecoder decoder,
    required Directory derivedRoot,
  }) : _decoder = decoder,
       _derivedRoot = derivedRoot;

  final StillDecoder _decoder;
  final Directory _derivedRoot;

  // ponytail: decode/encode runs on the caller isolate; wrap in Isolate.run
  // when this is wired into the UI.
  Future<DerivedImage?> ensure({
    required File source,
    required String assetId,
    required String checksum,
    required int targetLongSide,
  }) async {
    final bucket = bucketFor(targetLongSide);
    final cacheKey = cacheKeyFor(checksum: checksum, bucket: bucket);
    final destination = File(
      p.join(
        _derivedRoot.path,
        '${sanitizePathSegment(assetId)}-$cacheKey.jpg',
      ),
    );

    final cached = await _cached(destination, cacheKey);
    if (cached != null) {
      return cached;
    }

    final decoded = await _decoder.decode(source.path, maxLongSide: bucket);
    if (decoded == null) {
      return null;
    }
    if (decoded.width <= 0 ||
        decoded.height <= 0 ||
        decoded.bytes.length < decoded.width * decoded.height * 4) {
      return null;
    }

    final image = img.Image.fromBytes(
      width: decoded.width,
      height: decoded.height,
      bytes: decoded.bytes.buffer,
      numChannels: 4,
    );
    final longest = math.max(decoded.width, decoded.height);
    final widthIsLongest = decoded.width >= decoded.height;
    final resized = longest <= bucket
        ? image
        : img.copyResize(
            image,
            width: widthIsLongest
                ? bucket
                : _scaledSide(decoded.width, decoded.height, bucket),
            height: widthIsLongest
                ? _scaledSide(decoded.height, decoded.width, bucket)
                : bucket,
            interpolation: img.Interpolation.average,
          );
    final jpeg = img.encodeJpg(resized, quality: _jpegQuality);

    await _derivedRoot.create(recursive: true);
    final part = File('${destination.path}.part');
    try {
      await part.writeAsBytes(jpeg, flush: true);
      if (await destination.exists()) {
        await destination.delete();
      }
      await part.rename(destination.path);
    } catch (_) {
      if (await part.exists()) {
        await part.delete();
      }
      rethrow;
    }

    return DerivedImage(
      file: destination,
      width: resized.width,
      height: resized.height,
      sizeBytes: jpeg.length,
      cacheKey: cacheKey,
    );
  }

  Future<DerivedImage?> _cached(File destination, String cacheKey) async {
    if (!await destination.exists()) {
      return null;
    }
    final length = await destination.length();
    if (length <= 0) {
      return null;
    }
    final decoded = img.decodeJpg(await destination.readAsBytes());
    if (decoded == null) {
      return null;
    }
    return DerivedImage(
      file: destination,
      width: decoded.width,
      height: decoded.height,
      sizeBytes: length,
      cacheKey: cacheKey,
    );
  }

  static int bucketFor(int targetLongSide) {
    final rounded = ((targetLongSide + _bucketStep - 1) ~/ _bucketStep) *
        _bucketStep;
    return rounded.clamp(_minBucket, _maxBucket);
  }

  static String cacheKeyFor({required String checksum, required int bucket}) {
    final prefix = checksum.length > 8 ? checksum.substring(0, 8) : checksum;
    final safe = prefix.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    return 'v1-$safe-L$bucket';
  }

  static int _scaledSide(int side, int otherSide, int bucket) {
    final scaled = (side * bucket / otherSide).round();
    return scaled < 1 ? 1 : scaled;
  }
}
