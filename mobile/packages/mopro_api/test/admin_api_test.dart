import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for AdminApi
void main() {
  final instance = MoproApi().getAdminApi();

  group(AdminApi, () {
    // Create an order from a reservation (admin / internal)
    //
    //Future<Order> createOrder(String xIdempotencyKey, CreateOrderRequest createOrderRequest, { String xTraceId }) async
    test('test createOrder', () async {
      // TODO
    });

    // Create a new product listing (admin / seller onboarding)
    //
    //Future<Product> createProduct(String xIdempotencyKey, CreateProductRequest createProductRequest, { String xTraceId }) async
    test('test createProduct', () async {
      // TODO
    });

    // Get live commission and KDV rates for a category + market pair
    //
    //Future<CategoryCommission> getCategoryCommission(int id, { String xTraceId, String market }) async
    test('test getCategoryCommission', () async {
      // TODO
    });

    // Trigger a full refund for a delivered order (admin only)
    //
    //Future refundOrder(String xIdempotencyKey, int id, RefundOrderRequest refundOrderRequest, { String xTraceId }) async
    test('test refundOrder', () async {
      // TODO
    });

  });
}
