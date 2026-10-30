import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/domain/display/night_mode_service.dart';

DateTime at(int hour, int minute) => DateTime(2026, 1, 1, hour, minute);

void main() {
  group('NightModeService', () {
    test('activates within a daytime window with an exclusive end', () {
      bool active(int hour, int minute) => NightModeService.isActive(
        startMinutes: 600,
        endMinutes: 720,
        now: at(hour, minute),
      );

      expect(active(9, 59), isFalse);
      expect(active(10, 0), isTrue);
      expect(active(11, 59), isTrue);
      expect(active(12, 0), isFalse);
    });

    test('handles overnight windows', () {
      bool active(int hour, int minute) => NightModeService.isActive(
        startMinutes: 1320,
        endMinutes: 420,
        now: at(hour, minute),
      );

      expect(active(21, 59), isFalse);
      expect(active(22, 0), isTrue);
      expect(active(0, 0), isTrue);
      expect(active(6, 59), isTrue);
      expect(active(7, 0), isFalse);
      expect(active(12, 0), isFalse);
    });

    test('equal start and end is never active', () {
      expect(
        NightModeService.isActive(
          startMinutes: 480,
          endMinutes: 480,
          now: at(8, 0),
        ),
        isFalse,
      );
      expect(
        NightModeService.isActive(
          startMinutes: 480,
          endMinutes: 480,
          now: at(20, 0),
        ),
        isFalse,
      );
    });

    test('disabled is never active', () {
      expect(
        NightModeService.isActive(
          startMinutes: 1320,
          endMinutes: 420,
          now: at(23, 0),
          enabled: false,
        ),
        isFalse,
      );
    });
  });
}
