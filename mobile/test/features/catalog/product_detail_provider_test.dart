import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/catalog/providers/product_detail_provider.dart';
import 'package:mopro_api/mopro_api.dart';

Product _product(int id) => Product(
      id: id,
      sellerId: 1,
      sellerName: 'Seller A',
      categoryId: 10,
      brand: 'Brand X',
      status: ProductStatusEnum.active,
      title: 'Test Product',
      description: 'A product',
      variants: [
        Variant(
          id: 1,
          sku: 'SKU-1',
          priceMinor: 29999,
          priceCurrency: 'TRY',
          stock: 10,
          imageUrls: [],
        ),
      ],
      cashbackPreview: CashbackPreview(
        monthlyCoinMinor: 125,
        currency: 'TRY_COIN',
      ),
      createdAt: DateTime(2026),
    );

class _FakeCatalogApiOk extends CatalogApi {
  _FakeCatalogApiOk(this.productId) : super(Dio());
  final int productId;

  @override
  Future<Response<Product>> getProduct({
    required int id,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response(
        data: _product(id),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

class _FakeCatalogApiNotFound extends CatalogApi {
  _FakeCatalogApiNotFound() : super(Dio());

  @override
  Future<Response<Product>> getProduct({
    required int id,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

ProviderContainer _container(CatalogApi api) => ProviderContainer(
      overrides: [catalogApiProvider.overrideWithValue(api)],
    );

void main() {
  test('initial state is loading', () {
    final container = _container(_FakeCatalogApiOk(42));
    addTearDown(container.dispose);
    final s = container.read(productDetailProvider(42));
    expect(s, isA<AsyncLoading<Product>>());
  });

  test('loads product successfully', () async {
    final container = _container(_FakeCatalogApiOk(42));
    addTearDown(container.dispose);

    container.read(productDetailProvider(42));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s = container.read(productDetailProvider(42));
    expect(s.valueOrNull?.id, 42);
    expect(s.valueOrNull?.title, 'Test Product');
  });

  test('cashback preview populated correctly', () async {
    final container = _container(_FakeCatalogApiOk(1));
    addTearDown(container.dispose);

    container.read(productDetailProvider(1));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final product = container.read(productDetailProvider(1)).valueOrNull!;
    expect(product.cashbackPreview.monthlyCoinMinor, 125);
    expect(product.cashbackPreview.currency, 'TRY_COIN');
  });

  test('error state when product null', () async {
    final container = _container(_FakeCatalogApiNotFound());
    addTearDown(container.dispose);

    container.read(productDetailProvider(99));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s = container.read(productDetailProvider(99));
    expect(s, isA<AsyncError<Product>>());
    expect(s.error, isA<NotFoundError>());
  });
}
