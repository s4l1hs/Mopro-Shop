import 'package:dio/dio.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';

class OrderRepositoryImpl implements OrderRepository {
  const OrderRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<OrderListResult> listOrders({
    int page = 1,
    int perPage = 20,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/v1/orders',
      queryParameters: {'page': page, 'per_page': perPage},
    );
    final body = resp.data!;
    final data = (body['data'] as List<dynamic>)
        .map((e) => OrderDto.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = body['pagination'] as Map<String, dynamic>;
    final totalPages = (pagination['total_pages'] as num).toInt();
    return OrderListResult(
      data: data,
      hasMore: page < totalPages,
      totalPages: totalPages,
      currentPage: page,
    );
  }

  @override
  Future<OrderDto> getOrder(int id) async {
    final resp = await _dio.get<Map<String, dynamic>>('/v1/orders/$id');
    return OrderDto.fromJson(resp.data!);
  }

  @override
  Future<void> cancelOrder({required int id, String reason = ''}) async {
    await _dio.post<void>(
      '/v1/orders/$id/cancel',
      data: {'reason': reason},
    );
  }
}
