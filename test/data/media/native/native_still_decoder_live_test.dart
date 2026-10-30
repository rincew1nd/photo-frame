import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/media/native/native_still_decoder.dart';

void main() {
  final decoder = NativeStillDecoder.tryCreate();
  const skipReason = 'native still libraries are not available';

  for (final name in const ['sample.heic', 'sample.avif']) {
    test('decodes $name to 64x48 RGBA', () async {
      final file = File('test/fixtures/stills/$name');
      expect(file.existsSync(), isTrue, reason: 'missing fixture ${file.path}');

      final result = await decoder!.decode(file.path, maxLongSide: 320);

      expect(result, isNotNull);
      expect(result!.width, 64);
      expect(result.height, 48);
      expect(result.bytes.length, 64 * 48 * 4);
      expect(
        result.bytes.any((byte) => byte != 0),
        isTrue,
        reason: 'decoded pixels are entirely zero',
      );
    }, skip: decoder == null ? skipReason : null);
  }
}
