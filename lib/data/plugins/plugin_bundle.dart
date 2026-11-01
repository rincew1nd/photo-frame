import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'plugin_manifest.dart';

/// Configurable ZIP validation limits.
class PluginBundleLimits {
  const PluginBundleLimits({
    this.maxCompressedBytes = 20 * 1024 * 1024,
    this.maxExtractedBytes = 100 * 1024 * 1024,
    this.maxFiles = 500,
  });

  final int maxCompressedBytes;
  final int maxExtractedBytes;
  final int maxFiles;
}

/// A validated plugin bundle.
class PluginBundle {
  const PluginBundle({
    required this.manifest,
    required this.files,
    required this.sha256,
  });

  final PluginManifest manifest;

  /// Normalized bundle-relative file paths mapped to extracted bytes.
  final Map<String, Uint8List> files;

  /// SHA-256 hex digest of the original ZIP bytes.
  final String sha256;
}

/// Validates plugin ZIP bundles and returns their normalized contents.
class PluginBundleValidator {
  const PluginBundleValidator({this.limits = const PluginBundleLimits()});

  final PluginBundleLimits limits;

  PluginBundle validate(
    List<int> zipBytes, {
    Set<String> installedIds = const <String>{},
    required int hostApiVersion,
    required String hostAppVersion,
    PluginBundleLimits? limits,
  }) {
    final effectiveLimits = limits ?? this.limits;
    if (zipBytes.length > effectiveLimits.maxCompressedBytes) {
      throw PluginValidationException(
        'The plugin archive exceeds the '
        '${effectiveLimits.maxCompressedBytes} byte compressed limit.',
      );
    }

    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const PluginValidationException(
        'The plugin bundle is not a valid ZIP archive.',
      );
    }

    if (archive.length > effectiveLimits.maxFiles) {
      throw PluginValidationException(
        'The plugin archive contains more than '
        '${effectiveLimits.maxFiles} entries.',
      );
    }

    final normalizedNames = <String>{};
    final fileEntries = <_BundleEntry>[];
    var declaredExtractedBytes = 0;

    for (final entry in archive) {
      if (entry.isSymbolicLink || (entry.mode & 0xf000) == 0xa000) {
        throw const PluginValidationException(
          'Symbolic links are not allowed in plugin bundles.',
        );
      }

      final path = normalizePluginPath(entry.name, field: 'ZIP entry name');
      if (!normalizedNames.add(path)) {
        throw PluginValidationException('Duplicate ZIP entry "$path".');
      }

      if (entry.isDirectory) {
        continue;
      }

      final fileType = entry.mode & 0xf000;
      if (fileType != 0 && fileType != 0x8000) {
        throw PluginValidationException(
          'ZIP entry "$path" is not a regular file.',
        );
      }

      declaredExtractedBytes += entry.size;
      if (declaredExtractedBytes > effectiveLimits.maxExtractedBytes) {
        throw PluginValidationException(
          'The plugin archive exceeds the '
          '${effectiveLimits.maxExtractedBytes} byte extracted limit.',
        );
      }

      _rejectBlockedExtension(path);
      fileEntries.add(_BundleEntry(path: path, file: entry));
    }

    final paths = fileEntries.map((entry) => entry.path).toList();
    final prefix = _topLevelFolderPrefix(paths);

    final files = <String, Uint8List>{};
    var extractedBytes = 0;
    for (final entry in fileEntries) {
      final path = prefix.isEmpty
          ? entry.path
          : entry.path.substring(prefix.length);
      final remaining = effectiveLimits.maxExtractedBytes - extractedBytes;
      if (entry.file.size > remaining) {
        throw PluginValidationException(
          'The plugin archive exceeds the '
          '${effectiveLimits.maxExtractedBytes} byte extracted limit.',
        );
      }

      final bytes = _readBounded(entry.file, remaining, path);
      extractedBytes += bytes.length;
      _rejectNativeBinary(path, bytes);

      if (files.containsKey(path)) {
        throw PluginValidationException('Duplicate ZIP entry "$path".');
      }
      files[path] = bytes;
    }

    final manifestBytes = files['plugin.json'];
    if (manifestBytes == null) {
      throw const PluginValidationException(
        'The plugin bundle is missing plugin.json.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(manifestBytes));
    } on FormatException {
      throw const PluginValidationException(
        'plugin.json is not valid UTF-8 JSON.',
      );
    }

    final manifest = PluginManifest.fromJson(_jsonObject(decoded));

    final compatibilityIssue = manifest.compatibilityIssue(
      hostApiVersion: hostApiVersion,
      hostAppVersion: hostAppVersion,
    );
    if (compatibilityIssue != null) {
      throw PluginValidationException(compatibilityIssue);
    }

    if (installedIds.contains(manifest.id)) {
      throw PluginValidationException(
        'Plugin "${manifest.id}" is already installed.',
      );
    }

    if (!files.containsKey(manifest.entry)) {
      throw PluginValidationException(
        'The plugin entry "${manifest.entry}" is missing from the bundle.',
      );
    }

    final icon = manifest.icon;
    if (icon != null) {
      final iconBytes = files[icon];
      if (iconBytes == null) {
        throw PluginValidationException(
          'The plugin icon "$icon" is missing from the bundle.',
        );
      }
      _validateImage(icon, iconBytes, 'icon');
    }

    for (final screenshot in manifest.screenshots) {
      final screenshotBytes = files[screenshot];
      if (screenshotBytes == null) {
        throw PluginValidationException(
          'The plugin screenshot "$screenshot" is missing from the bundle.',
        );
      }
      _validateImage(screenshot, screenshotBytes, 'screenshot');
    }

    return PluginBundle(
      manifest: manifest,
      files: Map.unmodifiable(files),
      sha256: sha256.convert(zipBytes).toString(),
    );
  }
}

class _BundleEntry {
  const _BundleEntry({required this.path, required this.file});

  final String path;
  final ArchiveFile file;
}

const int _readChunkSize = 64 * 1024;

String _topLevelFolderPrefix(List<String> paths) {
  if (paths.isEmpty || paths.contains('plugin.json')) {
    return '';
  }

  final firstSegments = <String>{};
  for (final path in paths) {
    final slash = path.indexOf('/');
    if (slash <= 0) {
      return '';
    }
    firstSegments.add(path.substring(0, slash));
  }
  if (firstSegments.length != 1) {
    return '';
  }
  return '${firstSegments.single}/';
}

Uint8List _readBounded(ArchiveFile file, int remaining, String path) {
  try {
    final stream = file.getContent();
    if (stream == null) {
      throw PluginValidationException(
        'ZIP entry "$path" could not be extracted.',
      );
    }

    final builder = BytesBuilder(copy: false);
    var total = 0;
    while (!stream.isEOS) {
      final chunk = stream.readBytes(_readChunkSize).toUint8List();
      if (chunk.isEmpty) {
        break;
      }
      total += chunk.length;
      if (total > remaining) {
        throw const PluginValidationException(
          'The plugin archive exceeds the extracted size limit.',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  } on PluginValidationException {
    rethrow;
  } catch (_) {
    throw PluginValidationException(
      'ZIP entry "$path" could not be extracted.',
    );
  }
}

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const PluginValidationException(
          'plugin.json keys must be strings.',
        );
      }
      result[key] = entry.value;
    }
    return result;
  }
  throw const PluginValidationException(
    'plugin.json must contain a JSON object.',
  );
}

const Set<String> _blockedExtensions = <String>{
  '.aab',
  '.apk',
  '.bat',
  '.bin',
  '.bundle',
  '.class',
  '.cmd',
  '.com',
  '.deb',
  '.dex',
  '.dll',
  '.dylib',
  '.exe',
  '.jar',
  '.msi',
  '.node',
  '.ps1',
  '.rpm',
  '.scr',
  '.so',
  '.sys',
  '.vbs',
  '.war',
  '.wasm',
  '.wsf',
};

const Set<String> _imageExtensions = <String>{'.jpeg', '.jpg', '.png', '.webp'};

void _rejectBlockedExtension(String path) {
  final extension = p.posix.extension(path).toLowerCase();
  if (_blockedExtensions.contains(extension)) {
    throw PluginValidationException(
      'Native binaries and executables are not allowed '
      '("${p.posix.basename(path)}").',
    );
  }
}

void _rejectNativeBinary(String path, Uint8List bytes) {
  _rejectBlockedExtension(path);
  if (_hasNativeMagic(bytes)) {
    throw PluginValidationException(
      'Native binaries and executables are not allowed '
      '("${p.posix.basename(path)}").',
    );
  }
}

bool _hasNativeMagic(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x4d && bytes[1] == 0x5a) {
    return true;
  }
  if (bytes.length < 4) {
    return false;
  }
  // ELF
  if (bytes[0] == 0x7f &&
      bytes[1] == 0x45 &&
      bytes[2] == 0x4c &&
      bytes[3] == 0x46) {
    return true;
  }
  // Java class / Mach-O fat, WebAssembly, Android dex.
  if ((bytes[0] == 0xca &&
          bytes[1] == 0xfe &&
          bytes[2] == 0xba &&
          bytes[3] == 0xbe) ||
      (bytes[0] == 0x00 &&
          bytes[1] == 0x61 &&
          bytes[2] == 0x73 &&
          bytes[3] == 0x6d) ||
      (bytes[0] == 0x64 &&
          bytes[1] == 0x65 &&
          bytes[2] == 0x78 &&
          bytes[3] == 0x0a)) {
    return true;
  }
  // Mach-O
  return (bytes[0] == 0xfe &&
          bytes[1] == 0xed &&
          bytes[2] == 0xfa &&
          bytes[3] == 0xce) ||
      (bytes[0] == 0xce &&
          bytes[1] == 0xfa &&
          bytes[2] == 0xed &&
          bytes[3] == 0xfe) ||
      (bytes[0] == 0xfe &&
          bytes[1] == 0xed &&
          bytes[2] == 0xfa &&
          bytes[3] == 0xcf) ||
      (bytes[0] == 0xcf &&
          bytes[1] == 0xfa &&
          bytes[2] == 0xed &&
          bytes[3] == 0xfe);
}

void _validateImage(String path, Uint8List bytes, String field) {
  final extension = p.posix.extension(path).toLowerCase();
  if (!_imageExtensions.contains(extension)) {
    throw PluginValidationException(
      'The plugin $field "$path" must be a PNG, JPEG, or WebP image.',
    );
  }

  final valid = switch (extension) {
    '.png' => _hasPngMagic(bytes),
    '.jpg' || '.jpeg' => _hasJpegMagic(bytes),
    '.webp' => _hasWebpMagic(bytes),
    _ => false,
  };
  if (!valid) {
    throw PluginValidationException(
      'The plugin $field "$path" is not a valid image.',
    );
  }
}

bool _hasPngMagic(Uint8List bytes) {
  return bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;
}

bool _hasJpegMagic(Uint8List bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;
}

bool _hasWebpMagic(Uint8List bytes) {
  return bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;
}
