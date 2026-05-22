import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/utils/coin_formatter.dart';

void main() {
  group('formatCoin', () {
    test('compact — 500 minor → "5,00 MC"', () {
      expect(formatCoin(500, 'TRY_COIN'), '5,00 MC');
    });

    test('compact — 50000 minor → "500,00 MC"', () {
      expect(formatCoin(50000, 'TRY_COIN'), '500,00 MC');
    });

    test('compact — zero → "0,00 MC"', () {
      expect(formatCoin(0, 'TRY_COIN'), '0,00 MC');
    });

    test('compact — large value uses thousands separator', () {
      expect(formatCoin(10000000, 'TRY_COIN'), '100.000,00 MC');
    });

    test('full — uses "Mopro Coin" symbol', () {
      expect(
        formatCoin(50000, 'TRY_COIN', compact: false),
        '500,00 Mopro Coin',
      );
    });

    test('full — zero uses "Mopro Coin" symbol', () {
      expect(
        formatCoin(0, 'TRY_COIN', compact: false),
        '0,00 Mopro Coin',
      );
    });

    test('unknown currency code passed through as-is', () {
      expect(formatCoin(100, 'XYZ'), '1,00 XYZ');
    });
  });

  group('parsePeriod', () {
    test('"202601" → January 2026', () {
      final dt = parsePeriod('202601');
      expect(dt.year, 2026);
      expect(dt.month, 1);
    });

    test('"202512" → December 2025', () {
      final dt = parsePeriod('202512');
      expect(dt.year, 2025);
      expect(dt.month, 12);
    });
  });
}
