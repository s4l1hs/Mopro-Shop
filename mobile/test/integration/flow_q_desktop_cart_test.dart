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
import 'package:mopro/features/cart/widgets/empty_cart.dart';
import 'package:mopro/features/cart/widgets/order_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

// ── Flow Q — desktop Cart two-column + sticky summary + empty state ──────────────

CartLineDto _line(int i, int sellerId) => CartLineDto(
      id: 'line-$i',
      productId: i,
      variantId: 1,
      sellerId: sellerId,
      title: 'Ürün $i',
      priceMinor: 9900,
      qty: 1,
    );

/// Mutable fake so emptying the cart flips the screen to the empty state.
class _FakeCartRepo implements CartRepository {
  _FakeCartRepo(this._lines);
  List<CartLineDto> _lines;

  CartDto get _cart => CartDto(
        id: 'c-1',
        userId: 1,
        lines: _lines,
        totalsBySeller: [
          for (final id in _lines.map((l) => l.sellerId).toSet())
            SellerTotalDto(
              sellerId: id,
              itemsMinor: 9900,
              shippingMinor: 0,
              totalMinor: 9900,
            ),
        ],
        grandTotalMinor: 9900 * _lines.length,
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
  Future<void> removeLine({required String lineId}) async {
    _lines = _lines.where((l) => l.id != lineId).toList();
  }

  @override
  Future<void> clear() async => _lines = [];
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('Flow Q: two-column, sticky summary, empty after clear',
      (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final repo = _FakeCartRepo([
      for (var i = 0; i < 10; i++) _line(i, i.isEven ? 10 : 20),
    ]);

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          cartRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(theme: buildLightTheme(), home: const CartScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    container =
        ProviderScope.containerOf(tester.element(find.byType(CartScreen)));

    // Two-column layout renders.
    expect(find.byType(OrderSummaryCard), findsOneWidget);

    // Scroll items → summary stays pinned.
    final before = tester.getTopLeft(find.byType(OrderSummaryCard)).dy;
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(OrderSummaryCard)).dy,
      closeTo(before, 1.0),
    );

    // Empty the cart → full-width empty state, no summary card.
    await container.read(cartProvider.notifier).clear();
    await tester.pump();
    await tester.pump();
    expect(find.byType(EmptyCart), findsOneWidget);
    expect(find.byType(OrderSummaryCard), findsNothing);
  });
}
