import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';

final orderDetailProvider =
    NotifierProviderFamily<OrderDetailNotifier, AsyncValue<OrderDto>, int>(
  OrderDetailNotifier.new,
);

class OrderDetailNotifier extends FamilyNotifier<AsyncValue<OrderDto>, int> {
  @override
  AsyncValue<OrderDto> build(int arg) {
    _load();
    return const AsyncLoading();
  }

  Future<void> refresh() {
    state = const AsyncLoading();
    return _load();
  }

  /// Cancels the order, then re-fetches so the server-computed refund block and
  /// updated `actions` are reflected. Throws on failure so the caller (dialog)
  /// can keep itself open and surface the error.
  Future<void> cancelOrder({String reason = '', String note = ''}) async {
    final current = state.valueOrNull;
    final repo = ref.read(orderRepositoryProvider);
    await repo.cancelOrder(id: arg, reason: reason, note: note);
    // Optimistic local flip first (snappy), then authoritative refetch.
    if (current != null) {
      state = AsyncData(
        current.copyWith(status: OrderStatus.cancelled, updatedAt: DateTime.now()),
      );
    }
    await _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(orderRepositoryProvider);
      final order = await repo.getOrder(arg);
      state = AsyncData(order);
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
