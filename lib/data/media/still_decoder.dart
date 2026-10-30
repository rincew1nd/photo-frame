import 'dart:typed_data';

class DecodedRgba {
  const DecodedRgba({
    required this.bytes,
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final int width;
  final int height;
}

abstract class StillDecoder {
  Future<DecodedRgba?> decode(String path, {required int maxLongSide});
}
