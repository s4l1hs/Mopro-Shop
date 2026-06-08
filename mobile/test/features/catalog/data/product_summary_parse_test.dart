import 'package:flutter_test/flutter_test.dart';
import 'package:mopro_api/mopro_api.dart';

// The hand-written rail endpoints (recently-viewed / recommendations / similar /
// seller storefront) emit the shared buildProductSummaryJSON shape, now
// OpenAPI-compliant (F-021: cashback_preview.monthly_coin_minor, not
// monthly_amount_minor). Consumers parse it with the generated
// ProductSummary.fromJson — the manual mapper is retired. This guards that the
// spec shape parses, and that lowest_30d_price_minor carries through (P-030).
void main() {
  Map<String, dynamic> base() => {
        'id': 1,
        'seller_id': 1,
        'category_id': 1,
        'brand': 'Acme',
        'status': 'active',
        'title': 'Thing',
        'price_minor': 29999,
        'price_currency': 'TRY',
        'cashback_preview': {
          'monthly_coin_minor': 100,
          'currency': 'TRY_COIN',
        },
      };

  group('ProductSummary.fromJson on the /products (buildProductSummaryJSON) shape',
      () {
    test('parses the spec shape; maps lowest_30d_price_minor when present (P-030)',
        () {
      final p = ProductSummary.fromJson({
        ...base(),
        'lowest_30d_price_minor': 24999,
      });
      expect(p.lowest30dPriceMinor, 24999);
      expect(p.cashbackPreview.monthlyCoinMinor, 100);
    });

    test('lowest_30d_price_minor null when absent', () {
      expect(ProductSummary.fromJson(base()).lowest30dPriceMinor, isNull);
    });
  });
}
