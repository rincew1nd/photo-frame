import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/media/native/heif_bindings.dart';
import 'package:photoframe/data/media/native/libraw_bindings.dart';
import 'package:photoframe/data/media/native/native_still_decoder.dart';

void main() {
  test('tryOpen returns null for a missing library path', () {
    expect(
      LibRawBindings.tryOpen(libraryPath: 'definitely-missing-libraw-xyz'),
      isNull,
    );
  });

  test('tryCreate is null when neither native library is available', () {
    final raw = LibRawBindings.tryOpen();
    final heif = HeifBindings.tryOpen();
    final decoder = NativeStillDecoder.tryCreate();
    if (raw == null && heif == null) {
      expect(decoder, isNull);
    }
    // If either library is present, do not assert absence.
  });
}
