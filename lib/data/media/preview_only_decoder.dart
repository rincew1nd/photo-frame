import 'still_decoder.dart';

/// Safe fallback when native still-image libraries are unavailable: the
/// slideshow keeps using the server-rendered preview.
class PreviewOnlyStillDecoder implements StillDecoder {
  const PreviewOnlyStillDecoder();

  @override
  Future<DecodedRgba?> decode(String path, {required int maxLongSide}) async {
    return null;
  }
}
