import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mopro/core/utils/coin_formatter.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  group('formatPeriodLabel', () {
    test('"202601" → "Ocak 2026"', () {
      expect(formatPeriodLabel('202601'), 'Ocak 2026');
    });

    test('"202602" → "Şubat 2026"', () {
      expect(formatPeriodLabel('202602'), 'Şubat 2026');
    });

    test('"202512" → "Aralık 2025"', () {
      expect(formatPeriodLabel('202512'), 'Aralık 2025');
    });

    test('"202607" → "Temmuz 2026"', () {
      expect(formatPeriodLabel('202607'), 'Temmuz 2026');
    });
  });
}
