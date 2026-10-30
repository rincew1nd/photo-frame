import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/media/preview_only_decoder.dart';

void main() {
  test('PreviewOnlyStillDecoder never decodes', () async {
    const decoder = PreviewOnlyStillDecoder();

    expect(await decoder.decode('source.heic', maxLongSide: 320), isNull);
    expect(await decoder.decode('source.heic', maxLongSide: 3840), isNull);
  });
}
