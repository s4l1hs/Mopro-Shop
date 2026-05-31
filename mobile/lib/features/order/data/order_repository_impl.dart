import 'package:dio/dio.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';
import 'package:mopro/features/order/data/return_dto.dart';

class OrderRepositoryImpl implements OrderRepository {
  const OrderRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<OrderListResult> listOrders({
    int page = 1,
    int perPage = 20,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/orders',
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
    final resp = await _dio.get<Map<String, dynamic>>('/orders/$id');
    return OrderDto.fromJson(resp.data!);
  }

  @override
  Future<void> cancelOrder({
    required int id,
    String reason = '',
    String note = '',
  }) async {
    await _dio.post<void>(
      '/orders/$id/cancel',
      data: {
        'reason': reason,
        if (note.isNotEmpty) 'note': note,
      },
    );
  }

  @override
  Future<ReturnDetailDto> createReturn(CreateReturnRequest req) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/orders/${req.orderId}/returns',
      data: req.toJson(),
    );
    return ReturnDetailDto.fromJson(resp.data!);
  }

  @override
  Future<List<ReturnListItemDto>> listReturns({
    int limit = 20,
    int offset = 0,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/returns',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return (resp.data!['data'] as List<dynamic>)
        .map((e) => ReturnListItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ReturnDetailDto> getReturn(int id) async {
    final resp = await _dio.get<Map<String, dynamic>>('/returns/$id');
    return ReturnDetailDto.fromJson(resp.data!);
  }
}
