import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for CartApi
void main() {
  final instance = MoproApi().getCartApi();

  group(CartApi, () {
    // Add a variant to the cart; returns the updated enriched cart
    //
    // Returns the full enriched cart (same schema as GET /cart) in the response, eliminating the need for a follow-up GET round-trip. 
    //
    //Future<Cart> addCartItem(String xIdempotencyKey, AddCartItemRequest addCartItemRequest, { String xTraceId }) async
    test('test addCartItem', () async {
      // TODO
    });

    // Get the authenticated user's cart (enriched with product data)
    //
    // Returns enriched cart items joining variant/product data. Per-item `monthly_coin_minor` is the cashback preview. `subtotal_minor` and `total_monthly_coin_minor` are pre-computed sums. 
    //
    //Future<Cart> getCart({ String xTraceId }) async
    test('test getCart', () async {
      // TODO
    });

    // Release an active reservation (cancel checkout flow)
    //
    //Future releaseCart(String xIdempotencyKey, ReleaseCartRequest releaseCartRequest, { String xTraceId }) async
    test('test releaseCart', () async {
      // TODO
    });

    // Remove a variant from the cart
    //
    //Future removeCartItem(String xIdempotencyKey, int variantId, { String xTraceId }) async
    test('test removeCartItem', () async {
      // TODO
    });

    // Reserve inventory for all cart items before checkout
    //
    //Future<Reservation> reserveCart(String xIdempotencyKey, { String xTraceId }) async
    test('test reserveCart', () async {
      // TODO
    });

  });
}
