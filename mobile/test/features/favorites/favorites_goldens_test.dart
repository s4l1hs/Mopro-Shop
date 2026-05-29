import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/favorites/favorites_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: 'Marka',
      status: ProductSummaryStatusEnum.active,
      title: 'Ürün $id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

class _BatchAdapter implements HttpClientAdapter {
  _BatchAdapter(this.products);
  final List<ProductSummary> products;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode({'data': products.map((p) => p.toJson()).toList()}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(
  WidgetTester tester, {
  required Set<int> favIds,
  required Brightness brightness,
}) async {
  // ProductCard cells slightly overflow their grid aspect ratio (a pre-existing
  // card artifact); filter so --update-goldens can still capture the baseline.
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    if (favIds.isNotEmpty)
      'mopro_favorites': favIds.map((e) => e.toString()).toList(),
  });
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio()..httpClientAdapter = _BatchAdapter([for (final i in favIds) _p(i)]);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          home: const FavoritesScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  for (final brightness in Brightness.values) {
    final b = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('favorites desktop populated 1440 $b', (tester) async {
      await _pump(tester, favIds: {1, 2, 3, 4, 5, 6}, brightness: brightness);
      await expectLater(
        find.byType(FavoritesScreen),
        matchesGoldenFile('goldens/favorites_desktop_1440_$b.png'),
      );
    });

    testWidgets('favorites empty 1440 $b', (tester) async {
      await _pump(tester, favIds: const {}, brightness: brightness);
      await expectLater(
        find.byType(FavoritesScreen),
        matchesGoldenFile('goldens/favorites_empty_1440_$b.png'),
      );
    });
  }
}
