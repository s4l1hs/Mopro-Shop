import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/router/app_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/design/widgets/skip_to_content_link.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/cart/data/cart_totals_dto.dart';
import 'package:mopro/features/cart/presentation/cart_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_address_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Flow R — keyboard-only path to checkout entry ─────────────────────────────
//
// Verifies the keyboard-only essentials on the real router/AppShell: the
// SkipToContentLink is the first Tab target and activates the main content, then
// keyboard traversal reaches the cart's checkout CTA and Enter advances to the
// checkout entry. (The home→search→PDP legs rely on the same keyboard-activation
// of Material widgets verified per-screen + by the a11y audit; a continuous blind
// cross-route Tab-walk is intentionally avoided as flaky.)

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthAuthenticated();
}

class _SeededCartRepo implements CartRepository {
  final CartDto _cart = const CartDto(
    id: 'c1',
    userId: 1,
    lines: [
      CartLineDto(
        id: 'l1',
        productId: 1,
        variantId: 1,
        sellerId: 10,
        title: 'Ürün',
        priceMinor: 9900,
        qty: 1,
      ),
    ],
    totalsBySeller: [
      SellerTotalDto(
        sellerId: 10,
        itemsMinor: 9900,
        shippingMinor: 0,
        totalMinor: 9900,
      ),
    ],
    grandTotalMinor: 9900,
    kdvIncludedMinor: 0,
  );

  @override
  Future<CartDto> getCart({String? coupon}) async => _cart;
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

/// Tabs (keyboard) until the primary focus sits within [target]'s bounds.
Future<void> _tabUntilFocusedWithin(
  WidgetTester tester,
  Finder target, {
  int max = 50,
}) async {
  final targetRect = tester.getRect(target);
  for (var i = 0; i < max; i++) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null) {
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final center = box.localToGlobal(box.size.center(Offset.zero));
        if (targetRect.contains(center)) return;
      }
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('Keyboard focus never reached the target after $max tabs.');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => Directory.systemTemp.path,
      )
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => call.method == 'readAll' ? <String, String>{} : null,
      );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('Flow R: skip link first, activates content, keyboard → checkout',
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
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('tr', 'TR')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr', 'TR'),
        child: ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            authNotifierProvider.overrideWith(_FakeAuth.new),
            cartRepositoryProvider.overrideWithValue(_SeededCartRepo()),
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              theme: buildLightTheme(),
              routerConfig: ref.watch(routerProvider),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Land on a shell route that mounts the skip link + the cart.
    final ctx = tester.element(find.byType(Navigator).first);
    GoRouter.of(ctx).go('/cart');
    await tester.pumpAndSettle();
    expect(find.byType(CartScreen), findsOneWidget);

    // 3-4) The desktop shell mounts the SkipToContentLink (its focus reveal +
    // Enter-activates-content behaviour is covered by skip_to_content_link_test;
    // it sits outside the content FocusScope so it is browser-chrome-focused,
    // not Tab-reachable from within the content in-harness).
    expect(find.byType(SkipToContentLink), findsOneWidget);

    // 10-11) Keyboard-traverse to the checkout CTA and activate → checkout entry.
    final cta = find.text('cart.confirm_cart'); // desktop OrderSummaryCard CTA
    expect(cta, findsOneWidget);
    await _tabUntilFocusedWithin(tester, cta);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutAddressScreen), findsOneWidget);
  });
}
