import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photoframe/data/media/derived_image_service.dart';
import 'package:photoframe/data/media/still_decoder.dart';

class _FakeStillDecoder implements StillDecoder {
  _FakeStillDecoder({required this.width, required this.height});

  static const List<int> color = <int>[10, 20, 30, 255];
  final int width;
  final int height;
  bool returnNull = false;
  final List<({String path, int maxLongSide})> calls =
      <({String path, int maxLongSide})>[];

  @override
  Future<DecodedRgba?> decode(String path, {required int maxLongSide}) async {
    calls.add((path: path, maxLongSide: maxLongSide));
    if (returnNull) {
      return null;
    }
    final bytes = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      bytes[i * 4] = color[0];
      bytes[i * 4 + 1] = color[1];
      bytes[i * 4 + 2] = color[2];
      bytes[i * 4 + 3] = color[3];
    }
    return DecodedRgba(bytes: bytes, width: width, height: height);
  }
}

void main() {
  late Directory temporary;
  late Directory derived;
  late File source;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('photoframe_derived_');
    derived = Directory(p.join(temporary.path, 'derived'));
    await derived.create(recursive: true);
    source = File(p.join(temporary.path, 'source.heic'));
    await source.writeAsBytes(List<int>.generate(256, (index) => index));
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  group('bucketFor', () {
    test('rounds up to the next 320 step and clamps to 320..3840', () {
      expect(DerivedImageService.bucketFor(100), 320);
      expect(DerivedImageService.bucketFor(320), 320);
      expect(DerivedImageService.bucketFor(321), 640);
      expect(DerivedImageService.bucketFor(400), 640);
      expect(DerivedImageService.bucketFor(3840), 3840);
      expect(DerivedImageService.bucketFor(5000), 3840);
    });
  });

  group('cacheKeyFor', () {
    test('uses the first eight checksum characters', () {
      expect(
        DerivedImageService.cacheKeyFor(
          checksum: 'abcdef1234567890',
          bucket: 640,
        ),
        'v1-abcdef12-L640',
      );
    });

    test('uses a short checksum as-is and sanitizes separators', () {
      expect(
        DerivedImageService.cacheKeyFor(checksum: 'ab', bucket: 320),
        'v1-ab-L320',
      );
      expect(
        DerivedImageService.cacheKeyFor(checksum: 'ab/cd-ef12', bucket: 320),
        'v1-ab_cd_ef-L320',
      );
    });
  });

  group('ensure', () {
    test('creates a JPEG resized to the bucket without upscaling', () async {
      final decoder = _FakeStillDecoder(width: 640, height: 320);
      final service = DerivedImageService(
        decoder: decoder,
        derivedRoot: derived,
      );

      final result = await service.ensure(
        source: source,
        assetId: 'asset-1',
        checksum: 'abcdef1234567890',
        targetLongSide: 320,
      );

      expect(result, isNotNull);
      expect(result!.width, 320);
      expect(result.height, 160);
      expect(result.cacheKey, 'v1-abcdef12-L320');
      expect(
        p.basename(result.file.path),
        'asset-1-v1-abcdef12-L320.jpg',
      );
      expect(p.dirname(result.file.path), derived.path);
      expect(await result.file.exists(), isTrue);
      expect(result.sizeBytes, await result.file.length());

      final jpeg = img.decodeJpg(await result.file.readAsBytes());
      expect(jpeg, isNotNull);
      expect(jpeg!.width, 320);
      expect(jpeg.height, 160);

      expect(decoder.calls, hasLength(1));
      expect(decoder.calls.single.path, source.path);
      expect(decoder.calls.single.maxLongSide, 320);
      expect(await File('${result.file.path}.part').exists(), isFalse);
    });

    test('does not upscale a source smaller than the bucket', () async {
      final decoder = _FakeStillDecoder(width: 64, height: 32);
      final service = DerivedImageService(
        decoder: decoder,
        derivedRoot: derived,
      );

      final result = await service.ensure(
        source: source,
        assetId: 'asset-1',
        checksum: 'abcdef1234567890',
        targetLongSide: 2000,
      );

      expect(result, isNotNull);
      expect(result!.width, 64);
      expect(result.height, 32);
      expect(result.cacheKey, 'v1-abcdef12-L2240');
      expect(decoder.calls.single.maxLongSide, 2240);
    });

    test('reuses an existing cache entry without decoding', () async {
      final decoder = _FakeStillDecoder(width: 640, height: 320);
      final service = DerivedImageService(
        decoder: decoder,
        derivedRoot: derived,
      );

      final first = await service.ensure(
        source: source,
        assetId: 'asset-1',
        checksum: 'abcdef1234567890',
        targetLongSide: 320,
      );
      final second = await service.ensure(
        source: source,
        assetId: 'asset-1',
        checksum: 'abcdef1234567890',
        targetLongSide: 320,
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second!.file.path, first!.file.path);
      expect(second.width, first.width);
      expect(second.height, first.height);
      expect(second.sizeBytes, first.sizeBytes);
      expect(decoder.calls, hasLength(1));
    });

    test('invalidates on checksum or bucket changes', () async {
      final decoder = _FakeStillDecoder(width: 640, height: 320);
      final service = DerivedImageService(
        decoder: decoder,
        derivedRoot: derived,
      );

      final original = await service.ensure(
        source: source,
        assetId: 'asset-1',
        checksum: 'abcdef1234567890',
        targetLongSide: 320,
      );
      final newChecksum = await service.ensure(
        source: source,
        assetId: 'asset-1',
        checksum: 'ffffffff00000000',
        targetLongSide: 320,
      );
      final newBucket = await service.ensure(
        source: source,
        assetId: 'asset-1',
        checksum: 'abcdef1234567890',
        targetLongSide: 640,
      );

      expect(original, isNotNull);
      expect(newChecksum, isNotNull);
      expect(newBucket, isNotNull);
      expect(newChecksum!.file.path, isNot(original!.file.path));
      expect(newBucket!.file.path, isNot(original.file.path));
      expect(newBucket.cacheKey, 'v1-abcdef12-L640');
      expect(decoder.calls, hasLength(3));
      final files = await derived
          .list()
          .where((entry) => entry.path.endsWith('.jpg'))
          .toList();
      expect(files, hasLength(3));
    });

    test('returns null and writes nothing when the decoder fails', () async {
      final decoder = _FakeStillDecoder(width: 64, height: 32)
        ..returnNull = true;
      final service = DerivedImageService(
        decoder: decoder,
        derivedRoot: derived,
      );

      final result = await service.ensure(
        source: source,
        assetId: 'asset-1',
        checksum: 'abcdef1234567890',
        targetLongSide: 320,
      );

      expect(result, isNull);
      expect(await derived.list().toList(), isEmpty);
      expect(decoder.calls, hasLength(1));
    });

    test('leaves the source file untouched', () async {
      final before = await source.readAsBytes();
      final decoder = _FakeStillDecoder(width: 64, height: 32);
      final service = DerivedImageService(
        decoder: decoder,
        derivedRoot: derived,
      );

      await service.ensure(
        source: source,
        assetId: 'asset-1',
        checksum: 'abcdef1234567890',
        targetLongSide: 320,
      );

      expect(await source.readAsBytes(), before);
    });
  });
}
