import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro_api/mopro_api.dart';

ProductSummary _product() => ProductSummary(
      id: 1,
      sellerId: 1,
      categoryId: 10,
      brand: 'TestBrand',
      status: ProductSummaryStatusEnum.active,
      title: 'Harika Ürün',
      priceMinor: 29999,
      priceCurrency: 'TRY',
      coverImageUrl: null,
      cashbackPreview: CashbackPreview(
        monthlyCoinMinor: 125,
        currency: 'TRY_COIN',
      ),
    );

void main() {
  testWidgets('ProductCard shows product title', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductCard(
            product: _product(),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Harika Ürün'), findsOneWidget);
    await tester.tap(find.byType(GestureDetector).first);
    expect(tapped, isTrue);
  });

  testWidgets('ProductCard shows placeholder image icon when no URL',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductCard(
            product: _product(),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });
}
