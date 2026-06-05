import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/data/product_summary_api.dart';

// The rail summary mapper (recently-viewed / recommendations / similar) must
// carry lowest_30d_price_minor through to ProductSummary (P-030).
void main() {
  Map<String, dynamic> base() => {
        'id': 1,
        'price_minor': 29999,
        'price_currency': 'TRY',
        'cashback_preview': {
          'monthly_amount_minor': 100,
          'currency': 'TRY_COIN',
        },
      };

  group('productSummaryFromApi lowest_30d_price_minor (P-030)', () {
    test('maps the field when present', () {
      final p = productSummaryFromApi({
        ...base(),
        'lowest_30d_price_minor': 24999,
      });
      expect(p.lowest30dPriceMinor, 24999);
    });

    test('null when absent', () {
      expect(productSummaryFromApi(base()).lowest30dPriceMinor, isNull);
    });
  });
}
