import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/platform/paths.dart';
import 'package:photoframe/platform/services.dart';

void main() {
  test(
    'second instance fails to acquire and signals the first',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photo_frame_si_',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final paths = InMemoryAppPaths(directory);
      final first = FileLockSingleInstance(paths);
      final second = FileLockSingleInstance(paths);

      expect(await first.acquire(), isTrue);
      expect(await second.acquire(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await second.release();
      await first.release();

      final portFile = File(
        p.join(directory.path, 'support', 'photo_frame.port'),
      );
      expect(await portFile.exists(), isFalse);
    },
    skip: Platform.isWindows
        ? null
        : 'POSIX advisory locks are process-scoped, so two locks in the same '
              'process do not conflict; this test only exercises Windows.',
  );
}
