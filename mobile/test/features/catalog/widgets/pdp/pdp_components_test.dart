import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_price_block.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_seller_card.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_sticky_cta.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_variant_selector.dart';
import 'package:mopro_api/mopro_api.dart';

import '../../../../_support/test_harness.dart';

Variant _v(int id, {String? color, String? size, int stock = 10}) => Variant(
      id: id,
      sku: 'SKU$id',
      color: color,
      size: size,
      priceMinor: 12900,
      priceCurrency: 'TRY',
      stock: stock,
      imageUrls: const [],
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(initTestEnv);

  group('PdpPriceBlock', () {
    testWidgets('shows only the current price when no original', (tester) async {
      await _pump(tester, const PdpPriceBlock(priceMinor: 12900));
      expect(find.textContaining('129'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('shows strikethrough original + discount pill', (tester) async {
      await _pump(
        tester,
        const PdpPriceBlock(priceMinor: 7500, originalPriceMinor: 10000),
      );
      // (10000-7500)/10000 = 25%
      expect(find.text('%25'), findsOneWidget);
    });

    // P-030 lowest-30d line. .tr() returns the key in tests (bundle not loaded).
    testWidgets('hides the lowest-30d line when null', (tester) async {
      await _pump(tester, const PdpPriceBlock(priceMinor: 12900));
      expect(find.textContaining('product.lowest_30d'), findsNothing);
    });

    testWidgets('hides the lowest-30d line when it equals the price',
        (tester) async {
      await _pump(
        tester,
        const PdpPriceBlock(priceMinor: 12900, lowestIn30DaysMinor: 12900),
      );
      expect(find.textContaining('product.lowest_30d'), findsNothing);
    });

    testWidgets('shows the lowest-30d line when discounted and below the price',
        (tester) async {
      await _pump(
        tester,
        const PdpPriceBlock(
          priceMinor: 12900,
          originalPriceMinor: 15000,
          lowestIn30DaysMinor: 9900,
        ),
      );
      expect(find.textContaining('product.lowest_30d'), findsOneWidget);
    });

    // PDP-strikethrough gate alignment: the lowest-30d line is suppressed when
    // there is no strikethrough above it, even if lowest < price — matching the
    // card's `hasDiscount && lowest_30d < price` gate.
    testWidgets('hides the lowest-30d line when below price but no discount',
        (tester) async {
      await _pump(
        tester,
        const PdpPriceBlock(priceMinor: 12900, lowestIn30DaysMinor: 9900),
      );
      expect(find.textContaining('product.lowest_30d'), findsNothing);
    });

    // PD-03: the "Sepette %X" basket-discount pill (reuses the card's i18n key).
    testWidgets('shows the basket-discount pill when pct > 0', (tester) async {
      await _pump(
        tester,
        const PdpPriceBlock(priceMinor: 12900, basketDiscountPct: 10),
      );
      expect(find.textContaining('product.basket_discount'), findsOneWidget);
    });

    testWidgets('hides the basket-discount pill when null or 0', (tester) async {
      await _pump(tester, const PdpPriceBlock(priceMinor: 12900));
      expect(find.textContaining('product.basket_discount'), findsNothing);
      await _pump(
        tester,
        const PdpPriceBlock(priceMinor: 12900, basketDiscountPct: 0),
      );
      expect(find.textContaining('product.basket_discount'), findsNothing);
    });
  });

  group('PdpVariantSelector', () {
    testWidgets('renders nothing for a single variant', (tester) async {
      await _pump(
        tester,
        PdpVariantSelector(
          variants: [_v(1)],
          selected: _v(1),
          onChanged: (_) {},
        ),
      );
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('renders a chip per variant and reports taps', (tester) async {
      Variant? tapped;
      await _pump(
        tester,
        PdpVariantSelector(
          variants: [_v(1, color: 'Kırmızı'), _v(2, color: 'Mavi')],
          selected: _v(1, color: 'Kırmızı'),
          onChanged: (v) => tapped = v,
        ),
      );
      expect(find.byType(FilterChip), findsNWidgets(2));
      await tester.tap(find.text('Mavi'));
      expect(tapped?.id, 2);
    });

    testWidgets('out-of-stock variant is disabled + struck-through (P-015)',
        (tester) async {
      Variant? tapped;
      await _pump(
        tester,
        PdpVariantSelector(
          variants: [
            _v(1, color: 'Kırmızı', stock: 5),
            _v(2, color: 'Mavi', stock: 0),
          ],
          selected: _v(1, color: 'Kırmızı', stock: 5),
          onChanged: (v) => tapped = v,
        ),
      );
      final oosChip = tester.widget<FilterChip>(
        find.ancestor(of: find.text('Mavi'), matching: find.byType(FilterChip)),
      );
      expect(oosChip.onSelected, isNull); // disabled — can't select OOS
      await tester.tap(find.text('Mavi'), warnIfMissed: false);
      expect(tapped, isNull);
      final inStockChip = tester.widget<FilterChip>(
        find.ancestor(
          of: find.text('Kırmızı'),
          matching: find.byType(FilterChip),
        ),
      );
      expect(inStockChip.onSelected, isNotNull);
      final oosLabel = tester.widget<Text>(find.text('Mavi'));
      expect(oosLabel.style?.decoration, TextDecoration.lineThrough);
    });
  });

  group('PdpSellerCard', () {
    testWidgets('shows the name + store link when onTap provided',
        (tester) async {
      var tapped = false;
      await _pump(
        tester,
        PdpSellerCard(sellerName: 'Acme Store', onTap: () => tapped = true),
      );
      expect(find.text('Acme Store'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      expect(tapped, isTrue);
    });

    testWidgets('omits the link when onTap is null', (tester) async {
      await _pump(tester, const PdpSellerCard(sellerName: 'Acme Store'));
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('PdpStickyCta', () {
    testWidgets('disables the CTA when no variant is selected', (tester) async {
      await _pump(
        tester,
        PdpStickyCta(
          selectedVariant: null,
          isMutating: false,
          onAddToCart: () {},
        ),
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('enabled CTA fires onAddToCart', (tester) async {
      var added = false;
      await _pump(
        tester,
        PdpStickyCta(
          selectedVariant: _v(1),
          isMutating: false,
          onAddToCart: () => added = true,
        ),
      );
      await tester.tap(find.byType(FilledButton));
      expect(added, isTrue);
    });
  });
}
