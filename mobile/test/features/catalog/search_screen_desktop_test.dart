import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/plp/widgets/filter_panel.dart';
import 'package:mopro/features/catalog/screens/search_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/test_harness.dart';

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
    List<String>? attr,
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
          data: [_p(1, 'Adidas'), _p(2, 'Nike')],
          pagination: PaginationMeta(page: 1, perPage: 20, total: 2, totalPages: 1),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

Future<void> _pump(WidgetTester tester, Size size) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        searchApiProvider.overrideWithValue(_FakeSearchApi()),
      ],
      child: MaterialApp(theme: buildLightTheme(), home: const SearchScreen()),
    ),
  );
  await tester.pump();
  // Type a query → debounced search (300ms) → results.
  await tester.enterText(find.byType(TextField).first, 'nike');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('sidebar renders at >=768 with no category tree', (tester) async {
    await _pump(tester, const Size(1440, 1000));
    expect(find.byType(FilterPanel), findsOneWidget);
    // Category tree section hidden on search.
    expect(find.text('plp.filter_category'), findsNothing);
    expect(find.text('plp.filter_brand'), findsOneWidget);
    // Non-removable query chip (a Chip, not a deletable InputChip).
    expect(find.widgetWithText(Chip, '"nike"'), findsOneWidget);
  });

  testWidgets('no sidebar below 768', (tester) async {
    await _pump(tester, const Size(375, 900));
    expect(find.byType(FilterPanel), findsNothing);
  });
}
