import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/design/widgets/mopro_share_button.dart';
import 'package:mopro/features/account/browsing_history_screen.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/catalog/widgets/product_list_rail.dart';
import 'package:mopro/features/growth/meta_tags_service.dart';
import 'package:mopro/features/growth/seo_head.dart';
import 'package:mopro/features/growth/share_service.dart';
import 'package:mopro/features/growth/structured_data_service.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

// Tranche 5b growth flows. Seam/widget-level (not a full app boot): the per-route
// SEO/JSON-LD inputs are unit-tested in features/growth, the sitemap handler in
// cmd/core-svc; these flows exercise the cross-cutting wiring.

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

class _RecMeta implements MetaTagsService {
  MetaTagsInput? last;
  @override
  void setMetaTags(MetaTagsInput input) => last = input;
}

class _RecJsonLd implements StructuredDataService {
  Map<String, dynamic>? last;
  @override
  void setJsonLd(Map<String, dynamic> data) => last = data;
}

class _FakeShare extends ShareService {
  _FakeShare(this.outcome)
      : super(shareFn: (_, __) async {}, copyFn: (_) async {});
  final ShareOutcome outcome;
  String? lastText;
  @override
  Future<ShareOutcome> share({required String text, String? subject}) async {
    lastText = text;
    return outcome;
  }
}

class _FakeRecentlyViewed extends RecentlyViewedNotifier {
  _FakeRecentlyViewed(this._v);
  final AsyncValue<List<ProductSummary>> _v;
  @override
  AsyncValue<List<ProductSummary>> build() => _v;
}

class _FakeConsent extends UserConsentNotifier {
  @override
  UserConsent build() => const UserConsent(authed: true, analyticsEnabled: true);
  @override
  Future<bool> deleteAllData() async => true;
}

void main() {
  setUpAll(initTestEnv);

  // Flow JJ + NN: SeoHead drives BOTH the meta service and the JSON-LD service
  // from one per-route wrapper.
  testWidgets('Flow JJ/NN: SeoHead applies meta + JSON-LD together',
      (tester) async {
    final meta = _RecMeta();
    final jsonLd = _RecJsonLd();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metaTagsServiceProvider.overrideWithValue(meta),
          structuredDataServiceProvider.overrideWithValue(jsonLd),
        ],
        child: MaterialApp(
          home: SeoHead(
            meta: const MetaTagsInput(
              title: 'Ürün — Mopro',
              description: 'Açıklama',
              canonicalUrl: 'https://mopro.shop/products/1',
            ),
            jsonLd: productJsonLd(
              name: 'Ürün',
              description: 'Açıklama',
              url: 'https://mopro.shop/products/1',
              priceMinor: 20000,
              priceCurrency: 'TRY',
            ),
            child: const Text('x', textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(meta.last?.canonicalUrl, 'https://mopro.shop/products/1');
    expect(jsonLd.last?['@type'], 'Product');
    expect((jsonLd.last?['offers'] as Map)['price'], '200.00');
  });

  // Flow KK: web share success vs clipboard fallback (snackbar).
  testWidgets('Flow KK: share success → no snackbar; clipboard → snackbar',
      (tester) async {
    Future<void> pumpShare(ShareOutcome o) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [shareServiceProvider.overrideWithValue(_FakeShare(o))],
          child: MaterialApp(
            theme: buildLightTheme(),
            home: const Scaffold(
              body: MoproShareButton(
                url: 'https://mopro.shop/products/7',
                title: 'Ürün',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(MoproShareButton));
      await tester.pump();
    }

    await pumpShare(ShareOutcome.shared);
    expect(find.text('share.link_copied'), findsNothing);

    await pumpShare(ShareOutcome.copiedToClipboard);
    expect(find.text('share.link_copied'), findsOneWidget);
  });

  // Flow LL: home rail "see all" → browsing history → clear → empty.
  testWidgets('Flow LL: rail see-all routes to browsing history; clear empties',
      (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();

    final products = [_p(1), _p(2)];
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (ctx, __) => Scaffold(
            body: ProductListRail(
              products: products,
              title: 'Son baktıkların',
              onSeeAll: () => ctx.go('/account/browsing-history'),
            ),
          ),
        ),
        GoRoute(
          path: '/account/browsing-history',
          builder: (_, __) => const BrowsingHistoryScreen(),
        ),
        GoRoute(path: '/products/:id', builder: (_, __) => const Scaffold()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          recentlyViewedProvider
              .overrideWith(() => _FakeRecentlyViewed(AsyncData(products))),
          userConsentProvider.overrideWith(_FakeConsent.new),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Rail shows the see-all link; tap → browsing history grid renders.
    // (The clear→empty round-trip is covered in browsing_history_screen_test.)
    expect(find.text('home.see_all'), findsOneWidget);
    await tester.tap(find.text('home.see_all'));
    await tester.pumpAndSettle();
    expect(find.byType(BrowsingHistoryScreen), findsOneWidget);
    expect(find.byType(ProductCard), findsNWidgets(2));
  });
}
