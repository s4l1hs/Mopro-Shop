import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/widgets/cart_line_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

CartLineDto _line() => const CartLineDto(
      id: 'g-1',
      productId: 1,
      variantId: 1,
      sellerId: 10,
      title: 'Mopro Test Ürün',
      priceMinor: 29900,
      qty: 1,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('CartLineCard golden', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('tr', 'TR')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr', 'TR'),
        child: MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: RepaintBoundary(
              child: SizedBox(
                width: 400,
                child: CartLineCard(
                  line: _line(),
                  onRemove: () {},
                  onDecrement: () {},
                  onIncrement: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await expectLater(
      find.byType(CartLineCard),
      matchesGoldenFile('goldens/cart_line_card.png'),
    );
  });
}
