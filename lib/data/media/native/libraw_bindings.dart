import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:photoframe/data/media/still_decoder.dart';

// LibRaw: LIBRAW_IMAGE_JPEG = 1, LIBRAW_IMAGE_BITMAP = 2.
const int _libRawImageTypeBitmap = 2;

final class LibRawProcessedImage extends Struct {
  @Int32()
  external int type;
  @Uint16()
  external int height;
  @Uint16()
  external int width;
  @Uint16()
  external int colors;
  @Uint16()
  external int bits;
  @Uint32()
  external int dataSize;
}

typedef _InitNative = Pointer<Void> Function(Uint32);
typedef _OpenFileNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _SimpleIntNative = Int32 Function(Pointer<Void>);
typedef _CloseNative = Void Function(Pointer<Void>);
typedef _StrErrorNative = Pointer<Utf8> Function(Int32);
typedef _SetIntNative = Void Function(Pointer<Void>, Int32);
typedef _GetCamMulNative = Float Function(Pointer<Void>, Int32);
typedef _SetUserMulNative = Void Function(Pointer<Void>, Int32, Float);
typedef _MakeMemImageNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Int32>,
);

typedef _InitDart = Pointer<Void> Function(int);
typedef _OpenFileDart = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _SimpleIntDart = int Function(Pointer<Void>);
typedef _CloseDart = void Function(Pointer<Void>);
typedef _StrErrorDart = Pointer<Utf8> Function(int);
typedef _SetIntDart = void Function(Pointer<Void>, int);
typedef _GetCamMulDart = double Function(Pointer<Void>, int);
typedef _SetUserMulDart = void Function(Pointer<Void>, int, double);
typedef _MakeMemImageDart = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Int32>,
);

class LibRawBindings {
  LibRawBindings._(
    this._init,
    this._openFile,
    this._unpack,
    this._process,
    this._makeMemImage,
    this._clearMem,
    this._close,
    this._strError,
    this._setOutputBps,
    this._setOutputColor,
    this._setNoAutoBright,
    this._getCamMul,
    this._setUserMul,
  );

  final _InitDart _init;
  final _OpenFileDart _openFile;
  final _SimpleIntDart _unpack;
  final _SimpleIntDart _process;
  final _MakeMemImageDart _makeMemImage;
  final _CloseDart _clearMem;
  final _CloseDart _close;
  final _StrErrorDart _strError;
  final _SetIntDart _setOutputBps;
  final _SetIntDart _setOutputColor;
  final _SetIntDart _setNoAutoBright;
  final _GetCamMulDart _getCamMul;
  final _SetUserMulDart _setUserMul;

  String? _lastError;

  /// Human-readable message from the most recent failed libraw call.
  String? get lastError => _lastError;

  static LibRawBindings? tryOpen({String? libraryPath}) {
    final candidates = libraryPath != null
        ? <String>[libraryPath]
        : _platformCandidates();
    for (final candidate in candidates) {
      final DynamicLibrary library;
      try {
        library = DynamicLibrary.open(candidate);
      } catch (_) {
        continue;
      }
      return _fromLibrary(library);
    }
    return null;
  }

  static List<String> _platformCandidates() {
    if (Platform.isWindows) {
      return const ['raw.dll', 'libraw.dll'];
    }
    if (Platform.isAndroid) {
      return const ['libraw.so'];
    }
    if (Platform.isLinux) {
      return const ['libraw.so.23', 'libraw.so'];
    }
    return const ['libraw.so'];
  }

  static LibRawBindings? _fromLibrary(DynamicLibrary library) {
    try {
      return LibRawBindings._(
        library.lookupFunction<_InitNative, _InitDart>('libraw_init'),
        library.lookupFunction<_OpenFileNative, _OpenFileDart>(
          'libraw_open_file',
        ),
        library.lookupFunction<_SimpleIntNative, _SimpleIntDart>(
          'libraw_unpack',
        ),
        library.lookupFunction<_SimpleIntNative, _SimpleIntDart>(
          'libraw_dcraw_process',
        ),
        library.lookupFunction<_MakeMemImageNative, _MakeMemImageDart>(
          'libraw_dcraw_make_mem_image',
        ),
        library.lookupFunction<_CloseNative, _CloseDart>(
          'libraw_dcraw_clear_mem',
        ),
        library.lookupFunction<_CloseNative, _CloseDart>('libraw_close'),
        library.lookupFunction<_StrErrorNative, _StrErrorDart>(
          'libraw_strerror',
        ),
        library.lookupFunction<_SetIntNative, _SetIntDart>(
          'libraw_set_output_bps',
        ),
        library.lookupFunction<_SetIntNative, _SetIntDart>(
          'libraw_set_output_color',
        ),
        library.lookupFunction<_SetIntNative, _SetIntDart>(
          'libraw_set_no_auto_bright',
        ),
        library.lookupFunction<_GetCamMulNative, _GetCamMulDart>(
          'libraw_get_cam_mul',
        ),
        library.lookupFunction<_SetUserMulNative, _SetUserMulDart>(
          'libraw_set_user_mul',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  DecodedRgba? decode(String path) {
    final lr = _init(0);
    if (lr == nullptr) return null;

    final pathPtr = path.toNativeUtf8();
    Pointer<Void> imagePtr = nullptr;
    Pointer<Int32>? errPtr;
    try {
      if (!_check(_openFile(lr, pathPtr))) return null;
      if (!_check(_unpack(lr))) return null;

      for (var i = 0; i < 4; i++) {
        _setUserMul(lr, i, _getCamMul(lr, i));
      }
      _setOutputBps(lr, 8);
      _setOutputColor(lr, 1); // sRGB
      _setNoAutoBright(lr, 0);

      if (!_check(_process(lr))) return null;

      errPtr = calloc<Int32>();
      imagePtr = _makeMemImage(lr, errPtr);
      if (imagePtr == nullptr || errPtr.value != 0) {
        _lastError = 'libraw image creation failed (${errPtr.value})';
        return null;
      }

      final header = imagePtr.cast<LibRawProcessedImage>().ref;
      final width = header.width;
      final height = header.height;
      final colors = header.colors;
      final bits = header.bits;
      if (header.type != _libRawImageTypeBitmap ||
          width <= 0 ||
          height <= 0 ||
          (colors != 3 && colors != 4) ||
          (bits != 8 && bits != 16)) {
        _lastError = 'unexpected libraw image header';
        return null;
      }

      final pixels = width * height;
      final sampleBytes = bits ~/ 8;
      final needed = pixels * colors * sampleBytes;
      if (header.dataSize < needed) {
        _lastError = 'libraw image payload too small';
        return null;
      }

      final src = imagePtr.cast<Uint8>() + sizeOf<LibRawProcessedImage>();
      final out = Uint8List(pixels * 4);
      if (bits == 8) {
        final raw = src.asTypedList(needed);
        for (var p = 0; p < pixels; p++) {
          final s = p * colors;
          final d = p * 4;
          out[d] = raw[s];
          out[d + 1] = raw[s + 1];
          out[d + 2] = raw[s + 2];
          out[d + 3] = colors == 4 ? raw[s + 3] : 255;
        }
      } else {
        // ponytail: LibRaw emits host-endian 16-bit samples; targets are LE.
        final raw = ByteData.sublistView(src.asTypedList(needed));
        for (var p = 0; p < pixels; p++) {
          final s = p * colors * 2;
          final d = p * 4;
          out[d] = raw.getUint16(s, Endian.little) >> 8;
          out[d + 1] = raw.getUint16(s + 2, Endian.little) >> 8;
          out[d + 2] = raw.getUint16(s + 4, Endian.little) >> 8;
          out[d + 3] = colors == 4
              ? raw.getUint16(s + 6, Endian.little) >> 8
              : 255;
        }
      }
      return DecodedRgba(bytes: out, width: width, height: height);
    } finally {
      if (imagePtr != nullptr) _clearMem(imagePtr);
      if (errPtr != null) calloc.free(errPtr);
      _close(lr);
      malloc.free(pathPtr);
    }
  }

  bool _check(int code) {
    if (code == 0) return true;
    final message = _strError(code);
    _lastError = message == nullptr
        ? 'libraw error $code'
        : message.toDartString();
    return false;
  }
}
