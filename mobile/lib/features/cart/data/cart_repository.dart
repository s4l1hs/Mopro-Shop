import 'package:mopro/features/cart/data/cart_dto.dart';

abstract class CartRepository {
  /// [coupon] (CT-03) applies a coupon discount for display; the same code is
  /// passed at checkout to charge the discounted total.
  Future<CartDto> getCart({String? coupon});
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  });
  Future<CartDto> updateQty({required String lineId, required int qty});
  Future<void> removeLine({required String lineId});
  Future<void> clear();
}
