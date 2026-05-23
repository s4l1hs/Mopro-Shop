import 'package:mopro/features/order/data/order_dto.dart';

abstract class OrderRepository {
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20});
  Future<OrderDto> getOrder(int id);
  Future<void> cancelOrder({required int id, String reason = ''});
}
