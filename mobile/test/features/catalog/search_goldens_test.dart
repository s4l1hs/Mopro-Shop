import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/screens/search_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

ProductSummary _p(int id, String brand) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: brand,
      status: ProductSummaryStatusEnum.active,
      title: '$brand $id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

class _FakeSearchApi extends SearchApi {
  _FakeSearchApi() : super(Dio());

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
          data: [for (var i = 1; i <= 6; i++) _p(i, 'Marka')],
          pagination: PaginationMeta(page: 1, perPage: 20, total: 6, totalPages: 1),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
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

  testWidgets('search sidebar + query chip + filter chips 1440 light',
      (tester) async {
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        searchApiProvider.overrideWithValue(_FakeSearchApi()),
      ],
    );
    addTearDown(container.dispose);

    // Seed filter chips for the query's plp key.
    container.read(plpFiltersProvider(plpKeyForSearch('nike')).notifier).set(
          const PlpFilters(
            brands: ['Adidas'],
            ratingMin: 4,
            freeShippingOnly: true,
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: EasyLocalization(
          supportedLocales: const [Locale('tr', 'TR')],
          path: 'assets/translations',
          fallbackLocale: const Locale('tr', 'TR'),
          child: MaterialApp(
            theme: buildLightTheme(),
            home: const SearchScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'nike');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await expectLater(
      find.byType(SearchScreen),
      matchesGoldenFile('goldens/search_sidebar_1440_light.png'),
    );
  });
}
