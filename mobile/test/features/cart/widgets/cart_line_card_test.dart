import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/widgets/cart_line_card.dart';

CartLineDto _line() => const CartLineDto(
      id: 'line-1',
      productId: 1,
      variantId: 1,
      sellerId: 10,
      title: 'Test Ürün',
      priceMinor: 9900,
      qty: 2,
    );

Widget _wrap(Widget child) => EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('renders product title', (tester) async {
    bool removeCalled = false;

    await tester.pumpWidget(
      _wrap(
        CartLineCard(
          line: _line(),
          onRemove: () => removeCalled = true,
          onDecrement: () {},
          onIncrement: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Test Ürün'), findsOneWidget);
  });

  testWidgets('onRemove called on swipe', (tester) async {
    bool removeCalled = false;

    await tester.pumpWidget(
      _wrap(
        CartLineCard(
          line: _line(),
          onRemove: () => removeCalled = true,
          onDecrement: () {},
          onIncrement: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('line-1')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(removeCalled, true);
  });

  testWidgets('onIncrement called on + tap', (tester) async {
    bool incrementCalled = false;

    await tester.pumpWidget(
      _wrap(
        CartLineCard(
          line: _line(),
          onRemove: () {},
          onDecrement: () {},
          onIncrement: () => incrementCalled = true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    expect(incrementCalled, true);
  });

  testWidgets('onDecrement called on - tap', (tester) async {
    bool decrementCalled = false;

    await tester.pumpWidget(
      _wrap(
        CartLineCard(
          line: _line(),
          onRemove: () {},
          onDecrement: () => decrementCalled = true,
          onIncrement: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.remove));
    expect(decrementCalled, true);
  });
}
