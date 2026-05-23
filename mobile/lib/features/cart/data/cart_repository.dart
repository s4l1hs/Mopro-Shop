import 'package:mopro/features/cart/data/cart_dto.dart';

abstract class CartRepository {
  Future<CartDto> getCart();
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  });
  Future<CartDto> updateQty({required String lineId, required int qty});
  Future<void> removeLine({required String lineId});
  Future<void> clear();
}
