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

  Future<void> cancelOrder({String reason = ''}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final repo = ref.read(orderRepositoryProvider);
      await repo.cancelOrder(id: arg, reason: reason);
      state = AsyncData(
        OrderDto(
          id: current.id,
          userId: current.userId,
          sellerId: current.sellerId,
          status: OrderStatus.cancelled,
          totalMinor: current.totalMinor,
          itemsMinor: current.itemsMinor,
          shippingMinor: current.shippingMinor,
          commissionMinor: current.commissionMinor,
          kdvMinor: current.kdvMinor,
          currency: current.currency,
          createdAt: current.createdAt,
          updatedAt: DateTime.now(),
          shippedAt: current.shippedAt,
          deliveredAt: current.deliveredAt,
          items: current.items,
        ),
      );
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
