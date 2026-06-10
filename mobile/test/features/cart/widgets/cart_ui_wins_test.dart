import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/data/cart_totals_dto.dart';
import 'package:mopro/features/cart/widgets/cart_line_card.dart';
import 'package:mopro/features/cart/widgets/cart_totals_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Cart UI cheap-wins: CT-04 mobile breakdown + CT-05 move-to-favorites action.

CartLineDto _line() => const CartLineDto(
      id: 'line-1',
      productId: 1,
      variantId: 1,
      sellerId: 10,
      title: 'Test Ürün',
      priceMinor: 9900,
      qty: 2,
    );

CartDto _cart() => CartDto(
      id: 'c1',
      userId: 1,
      lines: [_line()],
      totalsBySeller: const [
        SellerTotalDto(
          sellerId: 10,
          itemsMinor: 19800,
          shippingMinor: 2500,
          totalMinor: 22300,
        ),
      ],
      grandTotalMinor: 22300,
      kdvIncludedMinor: 3700,
    );

Widget _wrap(Widget child) => EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('CT-05: move-to-favorites action shows + fires', (tester) async {
    var moved = 0;
    await tester.pumpWidget(
      _wrap(
        CartLineCard(
          line: _line(),
          onRemove: () {},
          onDecrement: () {},
          onIncrement: () {},
          onMoveToFavorites: () => moved++,
        ),
      ),
    );
    await tester.pump();

    final fav = find.byIcon(Icons.favorite_border);
    expect(fav, findsOneWidget);
    await tester.tap(fav);
    expect(moved, 1);
  });

  testWidgets('CT-05: action hidden when no callback', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CartLineCard(
          line: _line(),
          onRemove: () {},
          onDecrement: () {},
          onIncrement: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('CT-04: mobile summary shows subtotal + shipping breakdown',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        CartTotalsSummary(cart: _cart(), onCheckout: () {}),
      ),
    );
    await tester.pump();

    // Keyed (i18n not loaded in tests → keys render literally).
    expect(find.text('cart.subtotal'), findsOneWidget);
    expect(find.text('cart.shipping'), findsOneWidget);
  });
}
