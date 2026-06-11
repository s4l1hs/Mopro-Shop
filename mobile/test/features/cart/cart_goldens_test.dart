@Tags(['golden'])
library;

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/cart/data/cart_totals_dto.dart';
import 'package:mopro/features/cart/presentation/cart_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

CartLineDto _line(int i, int sellerId) => CartLineDto(
      id: 'line-$i',
      productId: i,
      variantId: 1,
      sellerId: sellerId,
      title: 'Ürün $i',
      priceMinor: 9900,
      qty: 1,
    );

class _FakeCartRepo implements CartRepository {
  _FakeCartRepo(this.lines);
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

Future<void> _pump(
  WidgetTester tester, {
  required List<CartLineDto> lines,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          cartRepositoryProvider.overrideWithValue(_FakeCartRepo(lines)),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          home: const CartScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
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

  for (final brightness in Brightness.values) {
    final b = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('cart two-column filled 1440 $b', (tester) async {
      await _pump(
        tester,
        lines: [_line(1, 10), _line(2, 10), _line(3, 20)],
        brightness: brightness,
      );
      await expectLater(
        find.byType(CartScreen),
        matchesGoldenFile('goldens/cart_two_col_filled_1440_$b.png'),
      );
    });

    testWidgets('cart empty 1440 $b', (tester) async {
      await _pump(tester, lines: const [], brightness: brightness);
      await expectLater(
        find.byType(CartScreen),
        matchesGoldenFile('goldens/cart_empty_1440_$b.png'),
      );
    });
  }
}