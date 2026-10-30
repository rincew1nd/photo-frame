import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:photoframe/data/media/still_decoder.dart';

// libheif enum values used for the interleaved RGBA decode path.
const int _heifColorspaceRgb = 1;
const int _heifChromaInterleavedRgba = 11;
const int _heifChannelInterleaved = 10;

final class HeifError extends Struct {
  @Int32()
  external int code;
  @Int32()
  external int subcode;
  external Pointer<Utf8> message;
}

typedef _ContextAllocNative = Pointer<Void> Function();
typedef _ContextFreeNative = Void Function(Pointer<Void>);
typedef _ReadFromFileNative = HeifError Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Void>,
);
typedef _GetPrimaryHandleNative = HeifError Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _HandleWidthNative = Int32 Function(Pointer<Void>);
typedef _HandleHeightNative = Int32 Function(Pointer<Void>);
typedef _DecodeImageNative = HeifError Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
  Int32,
  Int32,
  Pointer<Void>,
);
typedef _GetPlaneNative = Pointer<Uint8> Function(
  Pointer<Void>,
  Int32,
  Pointer<Int32>,
);
typedef _ReleaseNative = Void Function(Pointer<Void>);

typedef _ContextAllocDart = Pointer<Void> Function();
typedef _ContextFreeDart = void Function(Pointer<Void>);
typedef _ReadFromFileDart = HeifError Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Void>,
);
typedef _GetPrimaryHandleDart = HeifError Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _HandleWidthDart = int Function(Pointer<Void>);
typedef _HandleHeightDart = int Function(Pointer<Void>);
typedef _DecodeImageDart = HeifError Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
  int,
  int,
  Pointer<Void>,
);
typedef _GetPlaneDart = Pointer<Uint8> Function(
  Pointer<Void>,
  int,
  Pointer<Int32>,
);
typedef _ReleaseDart = void Function(Pointer<Void>);

class HeifBindings {
  HeifBindings._(
    this._contextAlloc,
    this._contextFree,
    this._readFromFile,
    this._getPrimaryHandle,
    this._handleWidth,
    this._handleHeight,
    this._decodeImage,
    this._getPlane,
    this._imageRelease,
    this._handleRelease,
  );

  final _ContextAllocDart _contextAlloc;
  final _ContextFreeDart _contextFree;
  final _ReadFromFileDart _readFromFile;
  final _GetPrimaryHandleDart _getPrimaryHandle;
  final _HandleWidthDart _handleWidth;
  final _HandleHeightDart _handleHeight;
  final _DecodeImageDart _decodeImage;
  final _GetPlaneDart _getPlane;
  final _ReleaseDart _imageRelease;
  final _ReleaseDart _handleRelease;

  String? _lastError;

  /// Human-readable message from the most recent failed libheif call.
  String? get lastError => _lastError;

  static HeifBindings? tryOpen({String? libraryPath}) {
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
      return const ['heif.dll', 'libheif.dll'];
    }
    if (Platform.isAndroid) {
      return const ['libheif.so'];
    }
    if (Platform.isLinux) {
      return const ['libheif.so.1', 'libheif.so'];
    }
    return const ['libheif.so'];
  }

  static HeifBindings? _fromLibrary(DynamicLibrary library) {
    try {
      return HeifBindings._(
        library.lookupFunction<_ContextAllocNative, _ContextAllocDart>(
          'heif_context_alloc',
        ),
        library.lookupFunction<_ContextFreeNative, _ContextFreeDart>(
          'heif_context_free',
        ),
        library.lookupFunction<_ReadFromFileNative, _ReadFromFileDart>(
          'heif_context_read_from_file',
        ),
        library.lookupFunction<_GetPrimaryHandleNative, _GetPrimaryHandleDart>(
          'heif_context_get_primary_image_handle',
        ),
        library.lookupFunction<_HandleWidthNative, _HandleWidthDart>(
          'heif_image_handle_get_width',
        ),
        library.lookupFunction<_HandleHeightNative, _HandleHeightDart>(
          'heif_image_handle_get_height',
        ),
        library.lookupFunction<_DecodeImageNative, _DecodeImageDart>(
          'heif_decode_image',
        ),
        library.lookupFunction<_GetPlaneNative, _GetPlaneDart>(
          'heif_image_get_plane',
        ),
        library.lookupFunction<_ReleaseNative, _ReleaseDart>(
          'heif_image_release',
        ),
        library.lookupFunction<_ReleaseNative, _ReleaseDart>(
          'heif_image_handle_release',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  DecodedRgba? decode(String path) {
    final context = _contextAlloc();
    if (context == nullptr) return null;

    final pathPtr = path.toNativeUtf8();
    Pointer<Void> handle = nullptr;
    Pointer<Void> image = nullptr;
    try {
      if (!_check(_readFromFile(context, pathPtr, nullptr))) return null;

      final handleOut = calloc<Pointer<Void>>();
      try {
        if (!_check(_getPrimaryHandle(context, handleOut))) return null;
        handle = handleOut.value;
      } finally {
        calloc.free(handleOut);
      }
      if (handle == nullptr) return null;

      final width = _handleWidth(handle);
      final height = _handleHeight(handle);
      if (width <= 0 || height <= 0) return null;

      final imageOut = calloc<Pointer<Void>>();
      try {
        if (!_check(
          _decodeImage(
            handle,
            imageOut,
            _heifColorspaceRgb,
            _heifChromaInterleavedRgba,
            nullptr,
          ),
        )) {
          return null;
        }
        image = imageOut.value;
      } finally {
        calloc.free(imageOut);
      }
      if (image == nullptr) return null;

      final stridePtr = calloc<Int32>();
      try {
        final plane = _getPlane(image, _heifChannelInterleaved, stridePtr);
        final stride = stridePtr.value;
        if (plane == nullptr || stride <= 0) return null;

        final bytes = Uint8List(width * height * 4);
        final rowBytes = width * 4;
        for (var y = 0; y < height; y++) {
          final row = (plane + y * stride).asTypedList(rowBytes);
          bytes.setRange(y * rowBytes, (y + 1) * rowBytes, row);
        }
        return DecodedRgba(bytes: bytes, width: width, height: height);
      } finally {
        calloc.free(stridePtr);
      }
    } finally {
      if (image != nullptr) _imageRelease(image);
      if (handle != nullptr) _handleRelease(handle);
      _contextFree(context);
      malloc.free(pathPtr);
    }
  }

  bool _check(HeifError error) {
    if (error.code == 0) return true;
    _lastError = error.message == nullptr
        ? 'libheif error ${error.code}/${error.subcode}'
        : error.message.toDartString();
    return false;
  }
}
