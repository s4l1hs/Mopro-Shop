import 'package:dio/dio.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';

class CartRepositoryImpl implements CartRepository {
  const CartRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<CartDto> getCart({String? coupon}) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/cart',
      queryParameters: (coupon != null && coupon.isNotEmpty)
          ? {'coupon': coupon}
          : null,
    );
    return CartDto.fromJson(resp.data!);
  }

  @override
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/cart/items',
      data: {
        'product_id': productId,
        'variant_id': variantId,
        'qty': qty,
      },
    );
    return CartDto.fromJson(resp.data!);
  }

  @override
  Future<CartDto> updateQty({
    required String lineId,
    required int qty,
  }) async {
    final resp = await _dio.put<Map<String, dynamic>>(
      '/cart/items/$lineId',
      data: {'qty': qty},
    );
    return CartDto.fromJson(resp.data!);
  }

  @override
  Future<void> removeLine({required String lineId}) async {
    await _dio.delete<void>('/cart/items/$lineId');
  }

  @override
  Future<void> clear() async {
    await _dio.delete<void>('/cart');
  }
}
