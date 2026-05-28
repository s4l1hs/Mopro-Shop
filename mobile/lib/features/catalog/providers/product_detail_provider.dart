import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';

final productDetailProvider =
    NotifierProviderFamily<ProductDetailNotifier, AsyncValue<Product>, int>(
  ProductDetailNotifier.new,
);

class ProductDetailNotifier
    extends FamilyNotifier<AsyncValue<Product>, int> {
  @override
  AsyncValue<Product> build(int arg) {
    Future<void>.microtask(_load);
    return const AsyncLoading();
  }

  Future<void> refresh() {
    state = const AsyncLoading();
    return _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(catalogApiProvider);
      final resp = await api.getProduct(id: arg);
      final product = resp.data;
      if (product == null) {
        state = AsyncError(
          const NotFoundError(resource: 'product'),
          StackTrace.current,
        );
      } else {
        state = AsyncData(product);
      }
    } on DioException catch (e, st) {
      final err = e.error;
      state = AsyncError(
        err is AppError ? err : NetworkError(message: e.message ?? ''),
        st,
      );
    } catch (e, st) {
      state = AsyncError(
        UnknownError(statusCode: 0, message: e.toString()),
        st,
      );
    }
  }
}
