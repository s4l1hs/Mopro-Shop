import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/auth/widgets/login_required.dart';
import 'package:mopro/features/catalog/pdp/reviews/rating_distribution_histogram.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_row.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

// ── Flow T — PDP reviews: histogram, guest gate, optimistic vote, sort, paging ──

Product _product() => Product(
      id: 123,
      sellerId: 1,
      sellerName: 'Acme Store',
      categoryId: 5,
      brand: 'Acme',
      status: ProductStatusEnum.active,
      attributes: const [],
      title: 'Test Ürünü',
      description: 'Kısa açıklama.',
      variants: [
        Variant(
          id: 1,
          sku: 'SKU1',
          color: 'Kırmızı',
          size: 'M',
          priceMinor: 12900,
          priceCurrency: 'TRY',
          stock: 10,
          // No image URLs → the PDP gallery skips cached_network_image (which
          // needs sqflite/path_provider plugins unavailable under flutter test).
          imageUrls: const [],
        ),
      ],
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
      createdAt: DateTime.utc(2026),
    );

class _FakeCatalogApi extends CatalogApi {
  _FakeCatalogApi() : super(Dio());

  @override
  Future<Response<Product>> getProduct({
    required int id,
    String? destCity,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response(data: _product(), requestOptions: RequestOptions(), statusCode: 200);
}

/// Serves 15 reviews with varied ratings, honouring sort + pagination so the flow
/// can verify refetch ordering and "Daha fazla".
class _ReviewsAdapter implements HttpClientAdapter {
  String? lastSort;
  int helpfulPosts = 0;

  static const _total = 15;

  List<Map<String, dynamic>> _all() => List.generate(_total, (i) {
        return {
          'id': i + 1,
          'userId': 100 + i,
          // ratings 1..5 cycling; exactly the i==4 review is a clean 5.
          'rating': 1 + (i % 5),
          'title': 'Yorum ${i + 1}',
          'body': 'Inceleme metni ${i + 1}.',
          'helpfulCount': (i * 7) % 11,
          'votedByCurrentUser': false,
          'createdAt': '2026-01-${(i % 28) + 1}T10:00:00Z',
        };
      });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path.contains('/helpful')) {
      helpfulPosts++;
      // Toggle: odd posts → voted true, even → voted false.
      final voted = helpfulPosts.isOdd;
      return ResponseBody.fromString(
        jsonEncode({'voted': voted, 'helpfulCount': voted ? 9 : 8}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final q = options.uri.queryParameters;
    final sort = q['sort'] ?? 'newest';
    lastSort = sort;
    final page = int.tryParse(q['page'] ?? '1') ?? 1;
    final all = _all();
    switch (sort) {
      case 'highest':
        all.sort((a, b) => (b['rating'] as int).compareTo(a['rating'] as int));
      case 'lowest':
        all.sort((a, b) => (a['rating'] as int).compareTo(b['rating'] as int));
      case 'helpful':
        all.sort(
          (a, b) => (b['helpfulCount'] as int).compareTo(a['helpfulCount'] as int),
        );
    }
    const pageSize = 10;
    final start = (page - 1) * pageSize;
    final items = all.skip(start).take(pageSize).toList();
    return ResponseBody.fromString(
      jsonEncode({
        'items': items,
        'total': _total,
        'page': page,
        'pageSize': pageSize,
        'summary': {
          'average': 3.2,
          'distribution': {'1': 3, '2': 3, '3': 3, '4': 3, '5': 3},
          'totalCount': _total,
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._initial);
  final AuthState _initial;
  @override
  Future<AuthState> build() async => _initial;
  void setAuthed() => state = const AsyncData(AuthAuthenticated());
}

void main() {
  setUpAll(() async {
    await initTestEnv();
    // cached_network_image (PDP gallery) reaches for path_provider; stub it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
  });

  testWidgets('Flow T: histogram, guest gate, optimistic vote, sort, pagination',
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
    final reviews = _ReviewsAdapter();
    final dio = Dio()..httpClientAdapter = reviews;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          catalogApiProvider.overrideWithValue(_FakeCatalogApi()),
          dioProvider.overrideWithValue(dio),
          authNotifierProvider.overrideWith(
            () => _FakeAuth(const AuthUnauthenticated()),
          ),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const ProductDetailScreen(productId: 123),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductDetailScreen)),
    );
    await container.read(authNotifierProvider.future); // pre-warm auth gate
    await tester.pumpAndSettle();

    // 3) Switch to the reviews tab.
    await tester.tap(find.text('product.reviews_tab'));
    await tester.pumpAndSettle();

    // 4) Histogram renders with 5 bars.
    expect(find.byType(RatingDistributionHistogram), findsOneWidget);
    await tester.ensureVisible(find.byType(RatingDistributionHistogram));
    await tester.pumpAndSettle();
    expect(find.byType(FractionallySizedBox), findsNWidgets(5));

    // 5) Guest taps "Faydalı" → desktop login dialog (not a bottom sheet).
    final firstHelpful = find.byIcon(Icons.thumb_up_alt_outlined).first;
    await tester.ensureVisible(firstHelpful);
    await tester.pumpAndSettle();
    // The PD-09 sticky buy-bar (64px, revealed once the buy-box scrolls away)
    // half-covers the icon at its scrolled-to resting spot (center lands at
    // exactly y=64, the bar's bottom edge) and the tab's scrollable is at max
    // extent — the center can't be hit. Tap the icon's exposed lower half;
    // the enclosing 40x40 button still receives it.
    // PD-09 layout shift: ensureVisible rests targets at the viewport's top
    // edge, where the revealed 64px sticky buy-bar overlays them — positional
    // taps can't reach. Nudge the page scroll back ~100px from a clear point
    // (y=500 — below the gallery PageView, which swallows drags) so the
    // target sits under the bar's edge, then tap for real.
    Future<void> nudgeClearOfBar() async {
      await tester.dragFrom(const Offset(720, 500), const Offset(0, 100));
      await tester.pumpAndSettle();
    }

    await nudgeClearOfBar();
    await tester.tap(firstHelpful);
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequired), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget); // desktop presenter
    expect(reviews.helpfulPosts, 0); // no vote was sent

    // 6) Dismiss the dialog (barrier tap) → count unchanged, no POST.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequired), findsNothing);
    expect(reviews.helpfulPosts, 0);

    // 7) Authenticate.
    (container.read(authNotifierProvider.notifier) as _FakeAuth).setAuthed();
    await tester.pumpAndSettle();

    // 8) Authed tap → optimistic vote + POST.
    await tester.ensureVisible(find.byIcon(Icons.thumb_up_alt_outlined).first);
    await tester.pumpAndSettle();
    await nudgeClearOfBar();
    await tester.tap(find.byIcon(Icons.thumb_up_alt_outlined).first);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(reviews.helpfulPosts, 1);

    // 9) Tap again → toggle off (second POST).
    await tester.ensureVisible(find.byIcon(Icons.thumb_up_alt_outlined).first);
    await tester.pumpAndSettle();
    await nudgeClearOfBar();
    await tester.tap(find.byIcon(Icons.thumb_up_alt_outlined).first);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(reviews.helpfulPosts, 2);

    // 10) Sort by "En yüksek puan" → refetch; first row rating is the max (5).
    await tester.ensureVisible(find.text('reviews.sort_newest'));
    await tester.pumpAndSettle();
    await nudgeClearOfBar();
    await tester.tap(find.text('reviews.sort_newest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('reviews.sort_highest').last);
    await tester.pumpAndSettle();
    expect(reviews.lastSort, 'highest');
    final firstRowStars = find.descendant(
      of: find.byType(ReviewRow).first,
      matching: find.byIcon(Icons.star_rounded),
    );
    expect(firstRowStars, findsNWidgets(5)); // top-rated review shows 5 filled stars

    // 11) Load more → list grows from 10 to 15; button disappears.
    expect(find.byType(ReviewRow), findsNWidgets(10));
    await tester.ensureVisible(find.text('reviews.load_more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('reviews.load_more'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(ReviewRow), findsNWidgets(15));
    expect(find.text('reviews.load_more'), findsNothing);
  });
}
