import 'package:photoframe/data/media/native/heif_bindings.dart';
import 'package:photoframe/data/media/native/libraw_bindings.dart';
import 'package:photoframe/data/media/still_decoder.dart';

class NativeStillDecoder implements StillDecoder {
  NativeStillDecoder._(this._heif, this._raw);

  final HeifBindings? _heif;
  final LibRawBindings? _raw;

  static NativeStillDecoder? tryCreate() {
    final heif = HeifBindings.tryOpen();
    final raw = LibRawBindings.tryOpen();
    if (heif == null && raw == null) return null;
    return NativeStillDecoder._(heif, raw);
  }

  bool get available => _heif != null || _raw != null;

  @override
  Future<DecodedRgba?> decode(String path, {required int maxLongSide}) async {
    final extension = path.toLowerCase();
    if (extension.endsWith('.heic') ||
        extension.endsWith('.heif') ||
        extension.endsWith('.avif')) {
      return _heif?.decode(path);
    }
    if (extension.endsWith('.dng')) {
      return _raw?.decode(path);
    }
    return null;
  }
}
