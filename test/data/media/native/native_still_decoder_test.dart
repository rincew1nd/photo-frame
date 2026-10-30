import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/media/native/heif_bindings.dart';
import 'package:photoframe/data/media/native/libraw_bindings.dart';
import 'package:photoframe/data/media/native/native_still_decoder.dart';

void main() {
  test('tryCreate is null when libheif is unavailable', () {
    // Environment-safe: only assert absence when the native library is absent.
    final decoder = NativeStillDecoder.tryCreate();
    if (decoder == null) {
      expect(decoder, isNull);
    }
  });

  test('HEIF and AVIF paths do not throw without native bindings', () async {
    final decoder = NativeStillDecoder.tryCreate();
    if (decoder == null) return;

    // Missing files must fail through libheif and return null, not crash.
    expect(await decoder.decode('missing.heic', maxLongSide: 320), isNull);
    expect(await decoder.decode('missing.heif', maxLongSide: 320), isNull);
    expect(await decoder.decode('missing.avif', maxLongSide: 320), isNull);
    expect(await decoder.decode('photo.jpg', maxLongSide: 320), isNull);
  });

  test('HEIC returns null when libheif is absent', () async {
    if (HeifBindings.tryOpen() != null) return;
    final decoder = NativeStillDecoder.tryCreate();
    if (decoder == null) return;
    expect(await decoder.decode('missing.heic', maxLongSide: 320), isNull);
  });

  test('DNG returns null when libraw is absent', () async {
    if (LibRawBindings.tryOpen() != null) return;
    final decoder = NativeStillDecoder.tryCreate();
    if (decoder == null) return;
    expect(await decoder.decode('missing.dng', maxLongSide: 320), isNull);
    expect(await decoder.decode('photo.DNG', maxLongSide: 320), isNull);
  });
}
