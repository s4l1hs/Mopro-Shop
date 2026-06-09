import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/home_provider.dart';
import 'package:mopro/features/catalog/screens/search_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SE-07 (no-results recovery) + SE-09 (mobile empty trending).

class _EmptySearchApi extends SearchApi {
  _EmptySearchApi() : super(Dio());

  @override
  Future<Response<ListProducts200Response>> search({
    required String q,
    List<String>? brand,
    int? rating,
    bool? freeShipping,
    bool? inStock,
    bool? priceDropped,
    String? xTraceId,
    int? categoryId,
    int? minPrice,
    int? maxPrice,
    String? sort = 'recommended',
    int? page = 1,
    int? perPage = 20,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response(
        data: ListProducts200Response(
          data: const [],
          pagination:
              PaginationMeta(page: 1, perPage: 8, total: 0, totalPages: 0),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

class _Cats extends CategoriesNotifier {
  @override
  CategoriesState build() => const CategoriesState(categories: AsyncData([]));
}

Future<void> _pump(WidgetTester tester, {required bool typeQuery}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      GoRoute(path: '/categories/:id', builder: (_, __) => const Scaffold()),
    ],
  );

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          searchApiProvider.overrideWithValue(_EmptySearchApi()),
          categoriesProvider.overrideWith(_Cats.new),
          trendingSearchesProvider
              .overrideWith((ref) async => ['nike', 'adidas']),
        ],
        child:
            MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
      ),
    ),
  );
  await tester.pump();
  if (typeQuery) {
    await tester.enterText(find.byType(TextField).first, 'zzxq');
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpAndSettle();
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

  testWidgets('SE-09: mobile empty state shows trending chips', (tester) async {
    await _pump(tester, typeQuery: false);
    expect(find.text('search.trending'), findsOneWidget);
    expect(find.text('nike'), findsOneWidget);
    expect(find.text('adidas'), findsOneWidget);
  });

  testWidgets('SE-07: a query with no results shows recovery (echo + trending)',
      (tester) async {
    await _pump(tester, typeQuery: true);
    expect(find.text('"zzxq"'), findsOneWidget); // query echo
    expect(find.text('empty_state.empty_message'), findsOneWidget);
    expect(find.text('search.trending'), findsOneWidget); // recovery trending
  });
}
