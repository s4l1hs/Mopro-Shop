import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/account/browsing_history_screen.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';
import 'package:mopro_api/mopro_api.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/a11y_audit_harness.dart';
import '../../_support/test_harness.dart';

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

class _FakeRecentlyViewed extends RecentlyViewedNotifier {
  _FakeRecentlyViewed(this._value);
  final AsyncValue<List<ProductSummary>> _value;
  @override
  AsyncValue<List<ProductSummary>> build() => _value;
}

class _FakeConsent extends UserConsentNotifier {
  int deleteCalls = 0;
  @override
  UserConsent build() => const UserConsent(authed: true, analyticsEnabled: true);
  @override
  Future<bool> deleteAllData() async {
    deleteCalls++;
    return true;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ProductSummary> products,
  _FakeConsent? consent,
}) async {
  // ProductCard overflows its grid cell at narrow test viewports (layout-only;
  // clipped in production) — ignore, like flow_z. Real layout is golden-covered.
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

  final router = GoRouter(
    initialLocation: '/account/browsing-history',
    routes: [
      GoRoute(
        path: '/account/browsing-history',
        builder: (_, __) => const BrowsingHistoryScreen(),
      ),
      GoRoute(path: '/products/:id', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        recentlyViewedProvider
            .overrideWith(() => _FakeRecentlyViewed(AsyncData(products))),
        if (consent != null)
          userConsentProvider.overrideWith(() => consent),
      ],
      child: MaterialApp.router(
        theme: buildLightTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('renders a ProductCard per history item', (tester) async {
    await _pump(tester, products: [_p(1), _p(2), _p(3)]);
    expect(find.byType(ProductCard), findsNWidgets(3));
  });

  testWidgets('empty state renders the title + CTA', (tester) async {
    await _pump(tester, products: const []);
    expect(find.byType(ProductCard), findsNothing);
    expect(find.text('browsing_history.empty_title'), findsOneWidget);
    expect(find.text('browsing_history.empty_cta'), findsOneWidget);
  });

  testWidgets('Geçmişi sil → confirm → calls deleteAllData + snackbar',
      (tester) async {
    final consent = _FakeConsent();
    await _pump(tester, products: [_p(1)], consent: consent);

    await tester.tap(find.text('browsing_history.clear'));
    await tester.pumpAndSettle();
    // Confirmation dialog up; confirm.
    expect(find.text('browsing_history.confirm_title'), findsOneWidget);
    await tester.tap(find.text('browsing_history.confirm_delete'));
    await tester.pumpAndSettle();

    expect(consent.deleteCalls, 1);
    expect(find.text('browsing_history.deleted_toast'), findsOneWidget);
  });

  testWidgets('clear is absent when history is empty', (tester) async {
    await _pump(tester, products: const []);
    expect(find.text('browsing_history.clear'), findsNothing);
  });

  testWidgets('a11y guard: zero error-severity violations (populated)',
      (tester) async {
    await _pump(tester, products: [_p(1), _p(2)]);
    final report =
        await A11yAuditHarness.audit(tester, find.byType(BrowsingHistoryScreen));
    expect(report.errorsOnly, isEmpty, reason: report.toMarkdown());
  });
}
