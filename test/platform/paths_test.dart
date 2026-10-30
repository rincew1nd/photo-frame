import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/platform/paths.dart';

void main() {
  test('cache extension mapping derives safe paths', () {
    expect(cacheExtensionForMimeType('image/jpeg'), '.jpg');
    expect(cacheExtensionForMimeType('image/png'), '.png');
    expect(cacheExtensionForMimeType('video/quicktime'), '.mov');
    expect(cacheExtensionForMimeType('video/mp4; codecs=avc1'), '.mp4');
    expect(cacheExtensionForMimeType('application/unknown'), '.bin');
    expect(cacheExtensionForMimeType(null), '.bin');

    final path = cacheFilePath(
      Directory.systemTemp,
      category: 'originals',
      assetId: 'a/b:c',
      mimeType: 'image/png',
    );
    expect(p.basename(path), 'a_b_c.png');
    expect(
      p.equals(p.dirname(path), p.join(Directory.systemTemp.path, 'originals')),
      isTrue,
    );
  });
}
