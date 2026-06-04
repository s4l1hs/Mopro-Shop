import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/utils/count_format.dart';

void main() {
  group('formatCompactCount (P-004)', () {
    test('hides below the threshold (< 10)', () {
      expect(formatCompactCount(0), '');
      expect(formatCompactCount(9), '');
    });

    test('raw for 10..999', () {
      expect(formatCompactCount(10), '10');
      expect(formatCompactCount(247), '247');
      expect(formatCompactCount(999), '999');
    });

    test('K-format for thousands, trailing .0 dropped', () {
      expect(formatCompactCount(1000), '1K');
      expect(formatCompactCount(1234), '1.2K');
      expect(formatCompactCount(12000), '12K');
      expect(formatCompactCount(12500), '12.5K');
    });

    test('M-format for millions', () {
      expect(formatCompactCount(1000000), '1M');
      expect(formatCompactCount(1500000), '1.5M');
    });
  });
}
