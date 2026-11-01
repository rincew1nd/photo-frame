import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/platform/services.dart';

void main() {
  test('windows autostart args add and delete the run value', () {
    const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

    expect(
      windowsAutostartArgs(r'C:\Program Files\Photo Frame\app.exe', true),
      <String>[
        'add',
        key,
        '/v',
        'PhotoFrame',
        '/t',
        'REG_SZ',
        '/d',
        r'"C:\Program Files\Photo Frame\app.exe"',
        '/f',
      ],
    );

    expect(
      windowsAutostartArgs(r'C:\Program Files\Photo Frame\app.exe', false),
      <String>['delete', key, '/v', 'PhotoFrame', '/f'],
    );
  });

  test('linux autostart entry is a desktop entry for the executable', () {
    final entry = linuxAutostartEntry('/opt/photo frame/photoframe');

    expect(entry, contains('[Desktop Entry]'));
    expect(entry, contains('Type=Application'));
    expect(entry, contains('Name=Photo Frame'));
    expect(entry, contains('Exec="/opt/photo frame/photoframe"'));
  });

  test('linux inhibit args block sleep and idle', () {
    final args = linuxInhibitArgs();

    expect(args, contains('--what=sleep:idle'));
    expect(args, contains('--mode=block'));
    expect(args.join(' '), contains('sleep infinity'));
  });
}
