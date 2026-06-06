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
import 'package:mopro/features/catalog/pdp/qa/qa_form_content.dart';
import 'package:mopro/features/catalog/pdp/qa/question_row.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

// ── Flow BB — Q&A: list renders, authed user asks a question, POST + confirm ──

Product _product() => Product(
      id: 123,
      sellerId: 1,
      sellerName: 'Acme Store',
      categoryId: 5,
      brand: 'Acme',
      status: ProductStatusEnum.active,
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

/// Serves the Q&A list (2 questions) and records the ask POST.
class _QaAdapter implements HttpClientAdapter {
  int questionPosts = 0;
  Map<String, dynamic>? lastPostBody;

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  List<Map<String, dynamic>> _questions() => [
        {
          'id': 1,
          'product_id': 123,
          'user_id': 100,
          'author_name': 'Ayşe K.',
          'body': 'Bedeni dar mı kalıyor?',
          'answer_count': 2,
          'created_at': '2026-05-01T10:00:00Z',
        },
        {
          'id': 2,
          'product_id': 123,
          'user_id': 101,
          'author_name': 'Mehmet T.',
          'body': 'Kargo ne kadar sürede gelir?',
          'answer_count': 0,
          'created_at': '2026-05-02T10:00:00Z',
        },
      ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (options.method == 'POST' && path.contains('/questions')) {
      questionPosts++;
      lastPostBody = options.data as Map<String, dynamic>?;
      return _json({
        'question': {
          'id': 3,
          'product_id': 123,
          'user_id': 100,
          'author_name': 'Test User',
          'body': lastPostBody?['body'] ?? '',
          'answer_count': 0,
          'created_at': '2026-05-31T10:00:00Z',
        },
      }, 201,);
    }
    if (path.contains('/questions')) {
      return _json({
        'data': _questions(),
        'total': 2,
        'page': 1,
        'hasMore': false,
      }, 200,);
    }
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

  testWidgets('Flow BB: Q&A list renders and an authed user asks a question',
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
    final adapter = _QaAdapter();
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

    // Open the Q&A tab.
    await tester.tap(find.text('product.qa_tab'));
    await tester.pumpAndSettle();

    // Both questions render.
    expect(find.byType(QuestionRow), findsNWidgets(2));
    expect(find.text('Bedeni dar mı kalıyor?'), findsOneWidget);

    // Ask a question.
    await tester.ensureVisible(find.text('qa.ask_cta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('qa.ask_cta'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestionFormContent), findsOneWidget);

    final field = find.descendant(
      of: find.byType(QuestionFormContent),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'Yıkamada renk verir mi?');
    await tester.pumpAndSettle();

    await tester.tap(find.text('qa.ask_submit'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(adapter.questionPosts, 1);
    expect(adapter.lastPostBody?['body'], 'Yıkamada renk verir mi?');
    expect(find.byType(QuestionFormContent), findsNothing);
    expect(find.text('qa.ask_success'), findsOneWidget);
  });
}
