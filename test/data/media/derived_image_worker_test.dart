import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/media/derived_image_worker.dart';
import 'package:photoframe/data/media/native/native_still_decoder.dart';
import 'package:photoframe/data/media/preview_only_decoder.dart';

void main() {
  late Directory temporary;
  late String derivedRootPath;
  late DerivedImageRequest request;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('photoframe_worker_');
    derivedRootPath = p.join(temporary.path, 'derived');
    request = DerivedImageRequest(
      sourcePath: p.join(temporary.path, 'missing.heic'),
      assetId: 'asset-1',
      checksum: 'abcdef1234567890',
      targetLongSide: 320,
      derivedRootPath: derivedRootPath,
    );
  });

  tearDown(() {
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  test('missing source returns null and writes nothing', () async {
    expect(await deriveImageInBackground(request), isNull);
    expect(Directory(derivedRootPath).existsSync(), isFalse);
    expect(temporary.listSync(), isEmpty);
  });

  test('worker is isolate-safe', () async {
    final result = await Isolate.run(() => deriveImageInBackground(request));

    expect(result, isNull);
    expect(Directory(derivedRootPath).existsSync(), isFalse);
    expect(temporary.listSync(), isEmpty);
  });

  test('stillDecoderProvider keeps the preview fallback', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final decoder = container.read(stillDecoderProvider);
    if (NativeStillDecoder.tryCreate() == null) {
      expect(decoder, isA<PreviewOnlyStillDecoder>());
    } else {
      expect(decoder, isA<NativeStillDecoder>());
    }
  });
}
