import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';
import 'package:mopro/features/order/data/order_repository_impl.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepositoryImpl(ref.watch(dioProvider));
});

// ── State ─────────────────────────────────────────────────────────────────────

class OrdersState {
  const OrdersState({
    this.orders = const AsyncLoading(),
    this.loadingMore = false,
    this.hasMore = false,
    this.currentPage = 1,
    this.loadMoreError,
  });

  final AsyncValue<List<OrderDto>> orders;
  final bool loadingMore;
  final bool hasMore;
  final int currentPage;
  final AppError? loadMoreError;

  OrdersState copyWith({
    AsyncValue<List<OrderDto>>? orders,
    bool? loadingMore,
    bool? hasMore,
    int? currentPage,
    AppError? loadMoreError,
    bool clearLoadMoreError = false,
  }) =>
      OrdersState(
        orders: orders ?? this.orders,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        currentPage: currentPage ?? this.currentPage,
        loadMoreError: clearLoadMoreError
            ? null
            : loadMoreError ?? this.loadMoreError,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final ordersProvider =
    NotifierProvider<OrdersNotifier, OrdersState>(OrdersNotifier.new);

// ── Notifier ──────────────────────────────────────────────────────────────────

class OrdersNotifier extends Notifier<OrdersState> {
  @override
  OrdersState build() {
    unawaited(_load(1));
    return const OrdersState();
  }

  Future<void> refresh() async {
    state = const OrdersState();
    await _load(1);
  }

  Future<void> loadNextPage() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(
      loadingMore: true,
      clearLoadMoreError: true,
    );
    await _load(state.currentPage + 1);
  }

  Future<void> _load(int page) async {
    try {
      final repo = ref.read(orderRepositoryProvider);
      final result = await repo.listOrders(page: page);
      final existing = page == 1
          ? <OrderDto>[]
          : state.orders.valueOrNull ?? <OrderDto>[];
      state = state.copyWith(
        orders: AsyncData([...existing, ...result.data]),
        hasMore: result.hasMore,
        currentPage: page,
        loadingMore: false,
        clearLoadMoreError: true,
      );
    } on DioException catch (e, st) {
      final err = e.error;
      final appError = err is AppError
          ? err
          : NetworkError(message: e.message ?? '');
      if (page == 1) {
        state = state.copyWith(orders: AsyncError(appError, st));
      } else {
        state =
            state.copyWith(loadMoreError: appError, loadingMore: false);
      }
    } catch (e, st) {
      final appError =
          UnknownError(statusCode: 0, message: e.toString());
      if (page == 1) {
        state = state.copyWith(orders: AsyncError(appError, st));
      } else {
        state =
            state.copyWith(loadMoreError: appError, loadingMore: false);
      }
    }
  }
}
