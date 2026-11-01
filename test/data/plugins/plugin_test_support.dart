import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const List<int> pngBytes = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
];

Map<String, dynamic> sampleManifest({
  String id = 'com.example.test',
  String version = '1.0.0',
  int apiVersion = 1,
  String minAppVersion = '1.0.0',
  String entry = 'index.html',
  String? icon,
  List<String>? screenshots,
  List<Object?>? inputs,
  List<String>? actions,
  List<String>? updateTriggers,
  Map<String, dynamic>? placement,
  Map<String, dynamic>? settings,
  Map<String, dynamic>? permissions,
}) {
  final manifest = <String, dynamic>{
    'id': id,
    'name': 'Test Plugin',
    'version': version,
    'apiVersion': apiVersion,
    'minAppVersion': minAppVersion,
    'author': 'Example Author',
    'license': 'MIT',
    'description': 'A test plugin.',
    'entry': entry,
    'permissions': permissions ?? <String, dynamic>{'network': false},
  };
  if (icon != null) {
    manifest['icon'] = icon;
  }
  if (screenshots != null) {
    manifest['screenshots'] = screenshots;
  }
  if (inputs != null) {
    manifest['inputs'] = inputs;
  }
  if (actions != null) {
    manifest['actions'] = actions;
  }
  if (updateTriggers != null) {
    manifest['updateTriggers'] = updateTriggers;
  }
  if (placement != null) {
    manifest['placement'] = placement;
  }
  if (settings != null) {
    manifest['settings'] = settings;
  }
  return manifest;
}

Uint8List buildZip(Map<String, List<int>> files, {String? prefix}) {
  final archive = Archive();
  for (final entry in files.entries) {
    final name = prefix == null ? entry.key : '$prefix/${entry.key}';
    archive.add(ArchiveFile.bytes(name, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

Uint8List buildBundleZip({
  Map<String, dynamic>? manifest,
  List<int>? manifestBytes,
  bool includeManifest = true,
  bool includeEntry = true,
  String? prefix,
  Map<String, List<int>> extraFiles = const <String, List<int>>{},
}) {
  final files = <String, List<int>>{
    if (includeManifest)
      'plugin.json':
          manifestBytes ??
          utf8.encode(jsonEncode(manifest ?? sampleManifest())),
    if (includeEntry) 'index.html': utf8.encode('<html></html>'),
    ...extraFiles,
  };
  return buildZip(files, prefix: prefix);
}

/// Builds a ZIP whose only entry is marked as a Unix symbolic link.
///
/// The archive encoder writes MS-DOS metadata, so the central-directory
/// "version made by" byte is patched to Unix after encoding. The decoder then
/// recognizes the 0xa000 file type and populates `symbolicLink`.
Uint8List buildSymlinkZip({
  String name = 'link',
  String target = 'index.html',
}) {
  final archive = Archive();
  final entry = ArchiveFile.bytes(name, utf8.encode(target));
  entry.mode = 0xa1ff;
  archive.add(entry);
  return _patchMadeByUnix(ZipEncoder().encodeBytes(archive));
}

Uint8List _patchMadeByUnix(Uint8List bytes) {
  final result = Uint8List.fromList(bytes);
  final eocd = _lastIndexOfSignature(result, const <int>[0x50, 0x4b, 0x05, 0x06]);
  if (eocd < 0) {
    throw StateError('End of central directory not found.');
  }

  final centralOffset = _readUint32Le(result, eocd + 16);
  var position = centralOffset;
  while (position + 46 <= result.length) {
    if (!_matchesSignature(
      result,
      position,
      const <int>[0x50, 0x4b, 0x01, 0x02],
    )) {
      break;
    }

    // versionMadeBy is a little-endian uint16; the low byte is the ZIP
    // version and the high byte identifies the host OS (3 = Unix).
    result[position + 5] = 3;

    final nameLength = _readUint16Le(result, position + 28);
    final extraLength = _readUint16Le(result, position + 30);
    final commentLength = _readUint16Le(result, position + 32);
    position += 46 + nameLength + extraLength + commentLength;
  }
  return result;
}

int _lastIndexOfSignature(Uint8List bytes, List<int> signature) {
  for (var index = bytes.length - signature.length; index >= 0; index--) {
    if (_matchesSignature(bytes, index, signature)) {
      return index;
    }
  }
  return -1;
}

bool _matchesSignature(Uint8List bytes, int offset, List<int> signature) {
  if (offset < 0 || offset + signature.length > bytes.length) {
    return false;
  }
  for (var index = 0; index < signature.length; index++) {
    if (bytes[offset + index] != signature[index]) {
      return false;
    }
  }
  return true;
}

int _readUint16Le(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _readUint32Le(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
