import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/data/cart_totals_dto.dart';
import 'package:mopro/features/checkout/presentation/checkout_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// CHK-01 (review breakdown) + CHK-02 (per-seller grouping) on the #176 cart.

CartLineDto _line(String id, int seller, String sellerName, int price) =>
    CartLineDto(
      id: id,
      productId: int.parse(id),
      variantId: int.parse(id),
      sellerId: seller,
      sellerName: sellerName,
      title: 'Ürün $id',
      variantLabel: 'Siyah, M',
      priceMinor: price,
      qty: 1,
    );

CartDto _cart() => CartDto(
      id: 'c1',
      userId: 1,
      lines: [
        _line('1', 10, 'Seller A', 10000),
        _line('2', 10, 'Seller A', 5000),
        _line('3', 20, 'Seller B', 8000),
      ],
      totalsBySeller: const [
        SellerTotalDto(
          sellerId: 10,
          itemsMinor: 15000,
          shippingMinor: 0,
          totalMinor: 15000,
        ),
        SellerTotalDto(
          sellerId: 20,
          itemsMinor: 8000,
          shippingMinor: 0,
          totalMinor: 8000,
        ),
      ],
      grandTotalMinor: 23000,
      kdvIncludedMinor: 3833,
    );

class _FakeCart extends CartNotifier {
  _FakeCart(this._s);
  final CartState _s;
  @override
  CartState build() => _s;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('CHK-01 breakdown + CHK-02 per-seller grouping', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('tr', 'TR')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr', 'TR'),
        child: ProviderScope(
          overrides: [
            cartProvider.overrideWith(
              () => _FakeCart(CartState(cart: AsyncData(_cart()))),
            ),
            cartMonthlyCashbackProvider.overrideWith((ref) async => 1200),
          ],
          child: const MaterialApp(home: CheckoutReviewScreen()),
        ),
      ),
    );
    await tester.pump();

    // CHK-01: breakdown rows (i18n not loaded → keys render literally).
    expect(find.text('cart.subtotal'), findsWidgets);
    expect(find.text('cart.shipping'), findsOneWidget);
    expect(find.text('checkout.total'), findsOneWidget);

    // CHK-02: a seller-group header per distinct seller (2).
    expect(find.text('cart.seller_section'), findsNWidgets(2));
  });
}
