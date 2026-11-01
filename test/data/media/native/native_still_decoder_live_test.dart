import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/media/native/native_still_decoder.dart';

bool _builtStillsAvailable() {
  // Live decode tests need the libraries produced by scripts/, not a system copy.
  if (Platform.isWindows) {
    return File('third_party/stills/win-x64/bin/heif.dll').existsSync();
  }
  if (Platform.isLinux) {
    return File('third_party/stills/linux-x64/lib/libheif.so').existsSync();
  }
  return false;
}

void main() {
  final decoder = NativeStillDecoder.tryCreate();
  final skipReason = decoder == null
      ? 'native still libraries are not available'
      : !_builtStillsAvailable()
      ? 'native still libraries are not built for this platform'
      : null;

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
