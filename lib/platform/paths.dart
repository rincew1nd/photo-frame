import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const List<String> cacheSubdirectories = <String>[
  'originals',
  'thumbnails',
  'live',
  'derived',
];

const Map<String, String> _mimeExtensions = <String, String>{
  'image/jpeg': '.jpg',
  'image/jpg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'image/gif': '.gif',
  'image/heic': '.heic',
  'image/heif': '.heif',
  'image/avif': '.avif',
  'video/mp4': '.mp4',
  'video/quicktime': '.mov',
  'video/webm': '.webm',
  'video/x-matroska': '.mkv',
  'application/octet-stream': '.bin',
};

/// Returns a [File] only when [path] is non-empty and exists on disk.
File? fileIfExists(String? path) {
  if (path == null || path.isEmpty) {
    return null;
  }
  final file = File(path);
  return file.existsSync() ? file : null;
}

String cacheExtensionForMimeType(String? mimeType) {
  if (mimeType == null) {
    return '.bin';
  }
  final normalized = mimeType.split(';').first.trim().toLowerCase();
  return _mimeExtensions[normalized] ?? '.bin';
}

String sanitizePathSegment(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return sanitized.isEmpty ? '_' : sanitized;
}

String cacheFilePath(
  Directory cacheRoot, {
  required String category,
  required String assetId,
  String? mimeType,
  String? variant,
}) {
  final name =
      '${sanitizePathSegment(assetId)}'
      '${variant == null ? '' : sanitizePathSegment(variant)}'
      '${cacheExtensionForMimeType(mimeType)}';
  final segments = category
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(sanitizePathSegment);
  return p.joinAll(<String>[cacheRoot.path, ...segments, name]);
}

/// Resolves the application's writable directories.
abstract class AppPaths {
  Future<Directory> support();
  Future<Directory> cache();
  Future<Directory> logs();
}

class FileSystemAppPaths implements AppPaths {
  Directory? _support;
  Directory? _cache;
  Directory? _logs;

  @override
  Future<Directory> support() async {
    return _support ??= (await getApplicationSupportDirectory())
      ..createSync(recursive: true);
  }

  @override
  Future<Directory> cache() async {
    if (_cache != null) {
      return _cache!;
    }
    final directory = await getApplicationCacheDirectory();
    directory.createSync(recursive: true);
    for (final name in cacheSubdirectories) {
      Directory(p.join(directory.path, name)).createSync(recursive: true);
    }
    return _cache = directory;
  }

  @override
  Future<Directory> logs() async {
    if (_logs != null) {
      return _logs!;
    }
    final base = await support();
    return _logs = Directory(p.join(base.path, 'logs'))
      ..createSync(recursive: true);
  }

}

class InMemoryAppPaths implements AppPaths {
  InMemoryAppPaths(this.baseDirectory);

  final Directory baseDirectory;

  Future<Directory> _child(String name) async {
    final directory = Directory(p.join(baseDirectory.path, name));
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<Directory> support() => _child('support');

  @override
  Future<Directory> cache() async {
    final directory = await _child('cache');
    for (final name in cacheSubdirectories) {
      await Directory(p.join(directory.path, name)).create(recursive: true);
    }
    return directory;
  }

  @override
  Future<Directory> logs() => _child('logs');
}
