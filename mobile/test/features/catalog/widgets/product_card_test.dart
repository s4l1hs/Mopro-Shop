import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:mopro_api/mopro_api.dart';

import '../../../_support/test_harness.dart';

ProductSummary _product({String? coverUrl}) => ProductSummary(
      id: 1,
      sellerId: 1,
      categoryId: 10,
      brand: 'TestBrand',
      status: ProductSummaryStatusEnum.active,
      title: 'Harika Ürün başlığı',
      priceMinor: 29999,
      priceCurrency: 'TRY',
      coverImageUrl: coverUrl,
      cashbackPreview: CashbackPreview(
        monthlyCoinMinor: 125,
        currency: 'TRY_COIN',
      ),
    );

Widget _card({VoidCallback? onTap}) => SizedBox(
      width: 200,
      height: 320,
      child: ProductCard(product: _product(), onTap: onTap ?? () {}),
    );

void main() {
  setUpAll(initTestEnv);

  group('ProductCard structure', () {
    testWidgets('renders brand, title, and tappable surface', (tester) async {
      var tapped = false;
      await pumpTrendyolApp(tester, _card(onTap: () => tapped = true));

      expect(find.text('TESTBRAND'), findsOneWidget);
      expect(find.text('Harika Ürün başlığı'), findsOneWidget);

      await tester.tap(find.byType(ProductCard));
      expect(tapped, isTrue);
    });

    testWidgets('shows placeholder icon when no cover image', (tester) async {
      await pumpTrendyolApp(tester, _card());
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('heart toggles favoritesProvider state', (tester) async {
      await pumpTrendyolApp(tester, _card());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProductCard)),
      );

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(container.read(favoritesProvider).contains(1), isFalse);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pump();

      expect(container.read(favoritesProvider).contains(1), isTrue);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });
  });

  group('ProductCard golden', () {
    testWidgets('light theme', (tester) async {
      await tester.binding.setSurfaceSize(const Size(220, 360));
      await pumpTrendyolApp(
        tester,
        Padding(padding: const EdgeInsets.all(8), child: _card()),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ProductCard),
        matchesGoldenFile('goldens/product_card_light.png'),
      );
    });

    testWidgets('dark theme', (tester) async {
      await tester.binding.setSurfaceSize(const Size(220, 360));
      await pumpTrendyolApp(
        tester,
        Padding(padding: const EdgeInsets.all(8), child: _card()),
        brightness: Brightness.dark,
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ProductCard),
        matchesGoldenFile('goldens/product_card_dark.png'),
      );
    });
  });
}
