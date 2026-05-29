import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/cart/data/cart_totals_dto.dart';
import 'package:mopro/features/cart/presentation/cart_screen.dart';
import 'package:mopro/features/cart/widgets/cart_totals_summary.dart';
import 'package:mopro/features/cart/widgets/empty_cart.dart';
import 'package:mopro/features/cart/widgets/order_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/test_harness.dart';

CartLineDto _line(String id, int sellerId) => CartLineDto(
      id: id,
      productId: int.parse(id.replaceAll(RegExp('[^0-9]'), '')),
      variantId: 1,
      sellerId: sellerId,
      title: 'Ürün $id',
      priceMinor: 9900,
      qty: 1,
    );

class _FakeCartRepo implements CartRepository {
  _FakeCartRepo({required this.lines});
  final List<CartLineDto> lines;

  CartDto get _cart => CartDto(
        id: 'c-1',
        userId: 1,
        lines: lines,
        totalsBySeller: [
          for (final id in lines.map((l) => l.sellerId).toSet())
            SellerTotalDto(
              sellerId: id,
              itemsMinor: 9900,
              shippingMinor: 0,
              totalMinor: 9900,
            ),
        ],
        grandTotalMinor: 9900 * lines.length,
        kdvIncludedMinor: 0,
      );

  @override
  Future<CartDto> getCart() async => _cart;
  @override
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async =>
      _cart;
  @override
  Future<CartDto> updateQty({required String lineId, required int qty}) async =>
      _cart;
  @override
  Future<void> removeLine({required String lineId}) async {}
  @override
  Future<void> clear() async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required List<CartLineDto> lines,
}) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cartRepositoryProvider.overrideWithValue(_FakeCartRepo(lines: lines)),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const CartScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('desktop renders two-column with the OrderSummaryCard',
      (tester) async {
    await _pump(
      tester,
      size: const Size(1440, 900),
      lines: [_line('p1', 10), _line('p2', 20)],
    );
    expect(find.byType(OrderSummaryCard), findsOneWidget);
    expect(find.byType(CartTotalsSummary), findsNothing);
  });

  testWidgets('summary stays pinned while the items list scrolls',
      (tester) async {
    await _pump(
      tester,
      size: const Size(1440, 900),
      lines: [for (var i = 0; i < 12; i++) _line('p$i', i.isEven ? 10 : 20)],
    );
    final before = tester.getTopLeft(find.byType(OrderSummaryCard)).dy;
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    final after = tester.getTopLeft(find.byType(OrderSummaryCard)).dy;
    expect(
      after,
      closeTo(before, 1.0),
      reason: 'order summary should stay pinned while items scroll',
    );
  });

  testWidgets('mobile keeps the bottom CartTotalsSummary (no summary card)',
      (tester) async {
    await _pump(
      tester,
      size: const Size(375, 800),
      lines: [_line('p1', 10)],
    );
    expect(find.byType(CartTotalsSummary), findsOneWidget);
    expect(find.byType(OrderSummaryCard), findsNothing);
  });

  testWidgets('empty cart renders full-width EmptyCart, no summary',
      (tester) async {
    await _pump(tester, size: const Size(1440, 900), lines: const []);
    expect(find.byType(EmptyCart), findsOneWidget);
    expect(find.byType(OrderSummaryCard), findsNothing);
  });
}
