import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/media/native/heif_bindings.dart';
import 'package:photoframe/data/media/native/native_still_decoder.dart';

void main() {
  test('tryOpen returns null for a missing library path', () {
    expect(
      HeifBindings.tryOpen(libraryPath: 'definitely-missing-libheif-xyz'),
      isNull,
    );
  });

  test('tryCreate is null when libheif is unavailable', () {
    final heif = HeifBindings.tryOpen();
    final decoder = NativeStillDecoder.tryCreate();
    if (heif == null) {
      expect(decoder, isNull);
    }
    // If libheif is present, do not assert absence.
  });
}
