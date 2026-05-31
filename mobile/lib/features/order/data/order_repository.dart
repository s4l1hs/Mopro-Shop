import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/return_dto.dart';

abstract class OrderRepository {
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20});
  Future<OrderDto> getOrder(int id);
  Future<void> cancelOrder({
    required int id,
    String reason = '',
    String note = '',
  });

  /// Submit a return request for delivered order items (POST /orders/{id}/returns).
  Future<ReturnDetailDto> createReturn(CreateReturnRequest req);

  /// The authenticated user's returns, newest first (GET /returns).
  Future<List<ReturnListItemDto>> listReturns({int limit = 20, int offset = 0});

  /// Full return detail (GET /returns/{id}).
  Future<ReturnDetailDto> getReturn(int id);
}
