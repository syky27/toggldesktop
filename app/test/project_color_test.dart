import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/util/project_color.dart';

void main() {
  group('projectColorHex', () {
    test('deterministic: same id → same colour', () {
      expect(projectColorHex(42), projectColorHex(42));
    });

    test('golden values match the reference algorithm', () {
      expect(projectColorHex(0), '#D74242');
      expect(projectColorHex(1), '#42D76D');
    });

    test('uppercase #RRGGBB format', () {
      final re = RegExp(r'^#[0-9A-F]{6}$');
      for (final id in [0, 1, 2, 7, 99, 12345]) {
        expect(re.hasMatch(projectColorHex(id)), isTrue, reason: 'id $id');
      }
    });

    test('golden angle spreads hues across ids', () {
      final seen = {for (var i = 0; i < 20; i++) projectColorHex(i)};
      expect(seen.length, greaterThan(15));
    });

    test('abs() handles negative ids', () {
      expect(projectColorHex(-1), projectColorHex(1));
      expect(projectColorHex(-7), projectColorHex(7));
    });

    test('null id → neutral grey', () {
      expect(projectColorHex(null), '#9E9E9E');
    });
  });
}
