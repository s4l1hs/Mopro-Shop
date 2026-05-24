import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/utils/money.dart';

void main() {
  group('MoneyUtils.cashbackMonthlyMinor', () {
    test('1 000 000 minor × 2000 bps → 12 820', () {
      expect(MoneyUtils.cashbackMonthlyMinor(1000000, 2000), 12820);
    });

    test('1 000 000 minor × 1000 bps → 6 410', () {
      expect(MoneyUtils.cashbackMonthlyMinor(1000000, 1000), 6410);
    });

    test('1 000 000 minor × 800 bps → 5 128', () {
      expect(MoneyUtils.cashbackMonthlyMinor(1000000, 800), 5128);
    });

    test('25 000 minor × 1500 bps → 240', () {
      expect(MoneyUtils.cashbackMonthlyMinor(25000, 1500), 240);
    });

    test('99 999 minor × 2000 bps → 1 282', () {
      expect(MoneyUtils.cashbackMonthlyMinor(99999, 2000), 1282);
    });
  });

  group('MoneyUtils.formatMinor', () {
    test('TRY — whole number', () {
      expect(MoneyUtils.formatMinor(150000), '₺1.500');
    });

    test('TRY — with cents', () {
      expect(MoneyUtils.formatMinor(150099), '₺1.500,99');
    });

    test('TRY_COIN', () {
      expect(MoneyUtils.formatMinor(12820, currency: 'TRY_COIN'), '128,20 ₺C');
    });

    test('zero', () {
      expect(MoneyUtils.formatMinor(0), '₺0');
    });
  });
}
