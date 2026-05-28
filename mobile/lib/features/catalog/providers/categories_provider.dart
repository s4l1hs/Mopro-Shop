import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';

class CategoriesState {
  const CategoriesState({
    this.categories = const AsyncLoading(),
  });

  final AsyncValue<List<Category>> categories;

  CategoriesState copyWith({AsyncValue<List<Category>>? categories}) =>
      CategoriesState(categories: categories ?? this.categories);
}

final categoriesProvider =
    NotifierProvider<CategoriesNotifier, CategoriesState>(
        CategoriesNotifier.new);

class CategoriesNotifier extends Notifier<CategoriesState> {
  @override
  CategoriesState build() {
    Future<void>.microtask(_load);
    return const CategoriesState();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    state = state.copyWith(categories: const AsyncLoading());
    try {
      final api = ref.read(catalogApiProvider);
      final resp = await api.listCategories();
      state = state.copyWith(
        categories: AsyncData(resp.data?.data ?? []),
      );
    } on DioException catch (e, st) {
      final err = e.error;
      state = state.copyWith(
        categories: AsyncError(
          err is AppError ? err : NetworkError(message: e.message ?? ''),
          st,
        ),
      );
    } catch (e, st) {
      state = state.copyWith(
        categories: AsyncError(
          UnknownError(statusCode: 0, message: e.toString()),
          st,
        ),
      );
    }
  }
}
