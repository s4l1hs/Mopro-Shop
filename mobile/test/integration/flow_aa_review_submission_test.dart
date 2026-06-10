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
import 'package:mopro/features/catalog/pdp/reviews/review_form_content.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

// ── Flow AA — review submission: eligibility CTA → form → POST → confirmation ──

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
          imageUrls: const [],
        ),
      ],
      cashbackPreview:
          CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
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
      Response(
        data: _product(),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

/// Serves the reviews tab: eligibility (canReview true), an empty review list,
/// and records the create POST.
class _ReviewWriteAdapter implements HttpClientAdapter {
  int reviewPosts = 0;
  Map<String, dynamic>? lastPostBody;

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.contains('/review-eligibility')) {
      return _json({
        'eligibility': {'canReview': true},
      }, 200,);
    }
    if (options.method == 'POST' && path.contains('/reviews')) {
      reviewPosts++;
      lastPostBody = options.data as Map<String, dynamic>?;
      return _json({
        'review': {
          'id': 1,
          'product_id': 123,
          'user_id': 100,
          'rating': lastPostBody?['rating'] ?? 5,
          'title': lastPostBody?['title'] ?? '',
          'body': lastPostBody?['body'] ?? '',
          'status': 'published',
          'created_at': '2026-05-31T10:00:00Z',
          'updated_at': '2026-05-31T10:00:00Z',
        },
      }, 201,);
    }
    if (path.contains('/reviews')) {
      return _json({
        'items': <Map<String, dynamic>>[],
        'total': 0,
        'page': 1,
        'pageSize': 10,
        'summary': {
          'average': 0.0,
          'distribution': {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
          'totalCount': 0,
        },
      }, 200,);
    }
    // /me and anything else: 404 (currentUserProvider tolerates the error).
    return _json({'error': 'not found'}, 404,);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._initial);
  final AuthState _initial;
  @override
  Future<AuthState> build() async => _initial;
}

void main() {
  setUpAll(() async {
    await initTestEnv();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
  });

  testWidgets('Flow AA: eligible user submits a review from the PDP CTA',
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
    final adapter = _ReviewWriteAdapter();
    final dio = Dio()..httpClientAdapter = adapter;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          catalogApiProvider.overrideWithValue(_FakeCatalogApi()),
          dioProvider.overrideWithValue(dio),
          authNotifierProvider.overrideWith(
            () => _FakeAuth(const AuthAuthenticated()),
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
    await container.read(authNotifierProvider.future);
    await tester.pumpAndSettle();

    // Open the reviews tab.
    await tester.tap(find.text('product.reviews_tab'));
    await tester.pumpAndSettle();

    // The eligibility-gated "Değerlendir" CTA is shown.
    expect(find.text('reviews.write_cta'), findsOneWidget);
    await tester.ensureVisible(find.text('reviews.write_cta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('reviews.write_cta'));
    await tester.pumpAndSettle();

    // The adaptive form opens (desktop dialog).
    expect(find.byType(ReviewFormContent), findsOneWidget);

    // Pick 5 stars (5th outline star in the picker).
    final stars = find.descendant(
      of: find.byType(ReviewFormContent),
      matching: find.byIcon(Icons.star_outline_rounded),
    );
    await tester.tap(stars.at(4));
    await tester.pumpAndSettle();

    // Body field is the second TextField in the form.
    final fields = find.descendant(
      of: find.byType(ReviewFormContent),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.last, 'Harika bir ürün.');
    await tester.pumpAndSettle();

    // Submit.
    await tester.tap(find.text('reviews.form_submit_new'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(adapter.reviewPosts, 1);
    expect(adapter.lastPostBody?['rating'], 5);
    expect(adapter.lastPostBody?['body'], 'Harika bir ürün.');
    // Form closed + confirmation SnackBar.
    expect(find.byType(ReviewFormContent), findsNothing);
    expect(find.text('reviews.submitted'), findsOneWidget);
  });
}
