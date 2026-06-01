import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/seller/data/seller_storefront_repository.dart';
import 'package:mopro/features/seller/screens/seller_storefront_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines are generated on Linux/CI via `make update-goldens`; the platform
// guard fails these on non-CI platforms with a remediation message.

const _slug = 'acme-store';

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'Ürün $id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      cashbackPreview:
          CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
    );

/// Canned storefront repository so the goldens are deterministic + offline.
class _FakeRepo extends SellerStorefrontRepository {
  _FakeRepo() : super(Dio());

  @override
  Future<SellerProfile> getProfile(String slug) async => const SellerProfile(
        id: 1,
        slug: _slug,
        displayName: 'Acme Store',
        bio: 'Acme Store — kaliteli ürünler, hızlı kargo. Tüm siparişlerde '
            'aynı gün kargo ve 14 gün koşulsuz iade.',
        logoImageUrl: null,
        bannerImageUrl: null,
        ratingAvg: 4.3,
        ratingCount: 128,
      );

  @override
  Future<(List<ProductSummary>, bool)> listProducts(
    String slug, {
    required int page,
  }) async =>
      ([for (var i = 0; i < 6; i++) _p(i + 1)], false);

  @override
  Future<(List<SellerReview>, bool)> listReviews(
    String slug, {
    required int page,
    required int pageSize,
  }) async =>
      (const <SellerReview>[], false);
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/sellers/$_slug',
    routes: [
      GoRoute(
        path: '/sellers/:slug',
        builder: (_, __) => const SellerStorefrontScreen(slug: _slug),
      ),
      GoRoute(path: '/products/:id', builder: (_, __) => const Scaffold()),
    ],
  );

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sellerStorefrontRepositoryProvider.overrideWithValue(_FakeRepo()),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          routerConfig: router,
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
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('seller storefront about mobile 375', (tester) async {
    await _pump(tester, const Size(375, 800));
    await expectLater(
      find.byType(SellerStorefrontScreen),
      matchesGoldenFile('goldens/seller_storefront_about_mobile_375.png'),
    );
  });

  testWidgets('seller storefront about desktop 1440', (tester) async {
    await _pump(tester, const Size(1440, 900));
    await expectLater(
      find.byType(SellerStorefrontScreen),
      matchesGoldenFile('goldens/seller_storefront_about_desktop_1440.png'),
    );
  });
}
