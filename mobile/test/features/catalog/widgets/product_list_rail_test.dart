import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/catalog/widgets/product_list_rail.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences _prefs;

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 42,
      brand: 'Acme',
      status: ProductSummaryStatusEnum.active,
      title: 'Ürün $id',
      priceMinor: 12900,
      priceCurrency: 'TRY',
      cashbackPreview:
          CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

Widget _wrap(Widget child) => ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('renders one ProductCard per product', (tester) async {
    await tester.pumpWidget(_wrap(
      ProductListRail(products: [_p(1), _p(2), _p(3)], title: 'Son baktıkların'),
    ),);
    await tester.pump();
    expect(find.byType(ProductCard), findsNWidgets(3));
    expect(find.text('Son baktıkların'), findsOneWidget);
  });

  testWidgets('empty list renders nothing', (tester) async {
    await tester.pumpWidget(_wrap(
      const ProductListRail(products: [], title: 'Son baktıkların'),
    ),);
    await tester.pump();
    expect(find.byType(ProductCard), findsNothing);
    expect(find.text('Son baktıkların'), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget); // the shrink
  });

  testWidgets('see-all link shows only when onSeeAll provided', (tester) async {
    await tester.pumpWidget(_wrap(
      ProductListRail(products: [_p(1)], title: 'T', onSeeAll: () {}),
    ),);
    await tester.pump();
    expect(find.text('home.see_all'), findsOneWidget);

    await tester.pumpWidget(_wrap(
      ProductListRail(products: [_p(1)], title: 'T'),
    ),);
    await tester.pump();
    expect(find.text('home.see_all'), findsNothing);
  });
}
