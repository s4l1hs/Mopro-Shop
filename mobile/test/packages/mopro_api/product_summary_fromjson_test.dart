import 'package:flutter_test/flutter_test.dart';
import 'package:mopro_api/mopro_api.dart';

// GEN-SYNC regression: the committed product_summary.g.dart deserializer had
// drifted and dropped isBestseller / basketDiscountPct, so the real API path read
// them false/null and the "Çok Satan" stamp + "Sepette %X" pill never rendered.
// Widget tests construct ProductSummary directly (bypassing fromJson), so they
// missed it — this test exercises the deserializer itself.

void main() {
  Map<String, dynamic> baseJson() => {
        'id': 1,
        'seller_id': 2,
        'category_id': 3,
        'brand': 'Nike',
        'status': 'active',
        'title': 'Air Max',
        'price_minor': 250000,
        'price_currency': 'TRY',
        'cashback_preview': {
          'monthly_coin_minor': 1200,
          'currency': 'TRY_COIN',
        },
      };

  test('ProductSummary.fromJson parses the merch fields', () {
    final json = baseJson()
      ..['is_bestseller'] = true
      ..['basket_discount_pct'] = 15;

    final p = ProductSummary.fromJson(json);

    expect(p.isBestseller, isTrue, reason: 'is_bestseller must deserialize');
    expect(
      p.basketDiscountPct,
      15,
      reason: 'basket_discount_pct must deserialize',
    );
  });

  test('ProductSummary.fromJson defaults merch fields when absent', () {
    final p = ProductSummary.fromJson(baseJson());

    // is_bestseller defaults to false (generator default); basket_discount_pct
    // is nullable → null when absent.
    expect(p.isBestseller, isFalse);
    expect(p.basketDiscountPct, isNull);
  });
}
