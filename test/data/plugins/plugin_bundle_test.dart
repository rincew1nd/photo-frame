import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/plugins/plugin_bundle.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';

import 'plugin_test_support.dart';

PluginBundle _validate(
  List<int> zipBytes, {
  PluginBundleLimits? limits,
  Set<String> installedIds = const <String>{},
  int hostApiVersion = supportedPluginApiVersion,
  String hostAppVersion = '2.0.0',
}) {
  return PluginBundleValidator().validate(
    zipBytes,
    limits: limits,
    installedIds: installedIds,
    hostApiVersion: hostApiVersion,
    hostAppVersion: hostAppVersion,
  );
}

Matcher _validationError(String messagePart) {
  return throwsA(
    isA<PluginValidationException>().having(
      (error) => error.message,
      'message',
      contains(messagePart),
    ),
  );
}

void main() {
  group('PluginBundleValidator valid bundles', () {
    test('accepts a bundle without a top-level folder', () {
      final zip = buildBundleZip(
        manifest: sampleManifest(
          icon: 'icon.png',
          screenshots: <String>['screenshots/shot.png'],
          inputs: <Object?>['time', 'config'],
        ),
        extraFiles: <String, List<int>>{
          'icon.png': pngBytes,
          'screenshots/shot.png': pngBytes,
        },
      );

      final bundle = _validate(zip);

      expect(bundle.manifest.id, 'com.example.test');
      expect(bundle.sha256, hasLength(64));
      expect(
        bundle.files.keys.toSet(),
        <String>{
          'plugin.json',
          'index.html',
          'icon.png',
          'screenshots/shot.png',
        },
      );
      expect(bundle.files['icon.png'], pngBytes);
    });

    test('accepts a bundle with one top-level folder and normalizes paths', () {
      final zip = buildBundleZip(
        prefix: 'clock',
        manifest: sampleManifest(
          icon: 'icon.png',
          screenshots: <String>['screenshots/shot.png'],
        ),
        extraFiles: <String, List<int>>{
          'icon.png': pngBytes,
          'screenshots/shot.png': pngBytes,
        },
      );

      final bundle = _validate(zip);

      expect(
        bundle.files.keys.toSet(),
        <String>{
          'plugin.json',
          'index.html',
          'icon.png',
          'screenshots/shot.png',
        },
      );
      expect(bundle.files.containsKey('clock/plugin.json'), isFalse);
    });

    test('returns a stable SHA-256 of the original ZIP', () {
      final zip = buildBundleZip();

      final first = _validate(zip);
      final second = _validate(zip);

      expect(first.sha256, second.sha256);
      expect(first.sha256, sha256.convert(zip).toString());
    });
  });

  group('PluginBundleValidator structure', () {
    test('rejects traversal paths', () {
      final zip = buildBundleZip(
        extraFiles: <String, List<int>>{
          '../evil.txt': utf8.encode('evil'),
        },
      );

      expect(() => _validate(zip), _validationError('..'));
    });

    test('rejects absolute paths', () {
      final zip = buildBundleZip(
        extraFiles: <String, List<int>>{
          '/evil.txt': utf8.encode('evil'),
        },
      );

      expect(() => _validate(zip), _validationError('relative path'));
    });

    test('rejects duplicate normalized names', () {
      final zip = buildZip(<String, List<int>>{
        'plugin.json': utf8.encode(jsonEncode(sampleManifest())),
        'index.html': utf8.encode('<html></html>'),
        './index.html': utf8.encode('<html>duplicate</html>'),
      });

      expect(() => _validate(zip), _validationError('Duplicate ZIP entry'));
    });

    test('rejects missing plugin.json', () {
      final zip = buildBundleZip(includeManifest: false);

      expect(() => _validate(zip), _validationError('missing plugin.json'));
    });

    test('rejects invalid manifest JSON', () {
      final zip = buildBundleZip(
        manifestBytes: utf8.encode('{ not json'),
      );

      expect(() => _validate(zip), _validationError('plugin.json'));
    });

    test('rejects non-object manifest JSON', () {
      final zip = buildBundleZip(manifestBytes: utf8.encode('[]'));

      expect(() => _validate(zip), _validationError('JSON object'));
    });

    test('rejects a missing entry document', () {
      final zip = buildBundleZip(includeEntry: false);

      expect(() => _validate(zip), _validationError('entry'));
    });

    test('rejects a missing icon', () {
      final zip = buildBundleZip(
        manifest: sampleManifest(icon: 'icon.png'),
      );

      expect(() => _validate(zip), _validationError('icon'));
    });

    test('rejects a missing screenshot', () {
      final zip = buildBundleZip(
        manifest: sampleManifest(screenshots: <String>['shot.png']),
      );

      expect(() => _validate(zip), _validationError('screenshot'));
    });

    test('rejects an invalid icon image', () {
      final zip = buildBundleZip(
        manifest: sampleManifest(icon: 'icon.png'),
        extraFiles: <String, List<int>>{
          'icon.png': utf8.encode('not an image'),
        },
      );

      expect(() => _validate(zip), _validationError('not a valid image'));
    });

    test('rejects an invalid screenshot image', () {
      final zip = buildBundleZip(
        manifest: sampleManifest(screenshots: <String>['shot.png']),
        extraFiles: <String, List<int>>{
          'shot.png': utf8.encode('not an image'),
        },
      );

      expect(() => _validate(zip), _validationError('not a valid image'));
    });

    test('rejects native binaries by extension', () {
      final zip = buildBundleZip(
        extraFiles: <String, List<int>>{
          'tool.exe': <int>[0x4d, 0x5a, 0x90, 0x00],
        },
      );

      expect(() => _validate(zip), _validationError('Native binaries'));
    });

    test('rejects native binaries by magic bytes', () {
      final zip = buildBundleZip(
        extraFiles: <String, List<int>>{
          'payload.dat': <int>[0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01, 0x01],
        },
      );

      expect(() => _validate(zip), _validationError('Native binaries'));
    });

    test('rejects symlinks', () {
      final zip = buildSymlinkZip();

      expect(() => _validate(zip), _validationError('Symbolic links'));
    });
  });

  group('PluginBundleValidator manifest validation', () {
    test('rejects unknown inputs', () {
      final zip = buildBundleZip(
        manifest: sampleManifest(inputs: <Object?>['secrets']),
      );

      expect(() => _validate(zip), _validationError('Unknown input'));
    });

    test('rejects invalid settings schemas', () {
      final zip = buildBundleZip(
        manifest: sampleManifest(
          settings: <String, dynamic>{
            'color': <String, dynamic>{
              'type': 'color',
              'label': 'Color',
              'default': 'red',
            },
          },
        ),
      );

      expect(
        () => _validate(zip),
        throwsA(isA<PluginValidationException>()),
      );
    });

    test('rejects an unsupported API version', () {
      final zip = buildBundleZip(
        manifest: sampleManifest(apiVersion: 2),
      );

      expect(() => _validate(zip), _validationError('API version'));
    });

    test('rejects an incompatible minimum app version', () {
      final zip = buildBundleZip(
        manifest: sampleManifest(minAppVersion: '99.0.0'),
      );

      expect(() => _validate(zip), _validationError('requires app version'));
    });

    test('rejects an already-installed plugin id', () {
      final zip = buildBundleZip();

      expect(
        () => _validate(
          zip,
          installedIds: <String>{'com.example.test'},
        ),
        _validationError('already installed'),
      );
    });
  });

  group('PluginBundleValidator limits', () {
    test('rejects archives over the compressed size limit', () {
      final zip = buildBundleZip();

      expect(
        () => _validate(
          zip,
          limits: PluginBundleLimits(
            maxCompressedBytes: zip.length - 1,
          ),
        ),
        _validationError('compressed limit'),
      );
    });

    test('rejects archives over the extracted size limit', () {
      final zip = buildBundleZip();

      expect(
        () => _validate(
          zip,
          limits: const PluginBundleLimits(maxExtractedBytes: 100),
        ),
        _validationError('extracted limit'),
      );
    });

    test('rejects archives over the file count limit', () {
      final zip = buildBundleZip();

      expect(
        () => _validate(
          zip,
          limits: const PluginBundleLimits(maxFiles: 1),
        ),
        _validationError('entries'),
      );
    });
  });
}
