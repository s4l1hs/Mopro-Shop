import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro_api/mopro_api.dart';

Category _cat(int id, String name) => Category(
      id: id,
      name: name,
      slug: name.toLowerCase(),
      commissionPctBps: 1000,
    );

ListCategories200Response _resp(List<Category> data) =>
    ListCategories200Response(data: data);

class _FakeCatalogApi extends CatalogApi {
  _FakeCatalogApi({this.categories = const [], this.error})
      : super(Dio());

  final List<Category> categories;
  final Exception? error;

  @override
  Future<Response<ListCategories200Response>> listCategories({
    String? xTraceId,
    int? depth,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (error != null) throw error!;
    return Response(
      data: _resp(categories),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );
  }
}

ProviderContainer _container(_FakeCatalogApi api) => ProviderContainer(
      overrides: [catalogApiProvider.overrideWithValue(api)],
    );

void main() {
  test('initial state is loading', () {
    final container = _container(_FakeCatalogApi());
    addTearDown(container.dispose);
    final s = container.read(categoriesProvider);
    expect(s.categories, isA<AsyncLoading<List<Category>>>());
  });

  test('loads categories successfully', () async {
    final api = _FakeCatalogApi(
      categories: [_cat(1, 'Elektronik'), _cat(2, 'Moda')],
    );
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(categoriesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s = container.read(categoriesProvider);
    expect(s.categories.valueOrNull?.length, 2);
    expect(s.categories.valueOrNull?.first.name, 'Elektronik');
  });

  test('empty list when API returns empty', () async {
    final container = _container(_FakeCatalogApi(categories: []));
    addTearDown(container.dispose);

    container.read(categoriesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s = container.read(categoriesProvider);
    expect(s.categories.valueOrNull, isEmpty);
  });

  test('error state on API failure', () async {
    final api = _FakeCatalogApi(error: Exception('network'));
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(categoriesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s = container.read(categoriesProvider);
    expect(s.categories, isA<AsyncError<List<Category>>>());
  });
}
