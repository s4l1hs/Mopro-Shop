import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for OrdersApi
void main() {
  final instance = MoproApi().getOrdersApi();

  group(OrdersApi, () {
    // Cancel an order (only while in pending/confirmed status)
    //
    //Future cancelOrder(String xIdempotencyKey, int id, { String xTraceId }) async
    test('test cancelOrder', () async {
      // TODO
    });

    // Atomically reserve cart → create order → initiate PSP payment
    //
    // Single-shot convenience endpoint for the mobile checkout flow. Internally calls cart.Reserve → order.Create → payment.Initiate. Returns immediately with redirect_url for 3DS if required, or order details for non-3DS payment methods. 
    //
    //Future<CheckoutResponse> checkout(String xIdempotencyKey, CheckoutRequest checkoutRequest, { String xTraceId }) async
    test('test checkout', () async {
      // TODO
    });

    // Create an order from a reservation (admin / internal)
    //
    //Future<Order> createOrder(String xIdempotencyKey, CreateOrderRequest createOrderRequest, { String xTraceId }) async
    test('test createOrder', () async {
      // TODO
    });

    // Submit a return request for delivered order items
    //
    //Future<ModelReturn> createReturn(String xIdempotencyKey, int id, ReturnRequest returnRequest, { String xTraceId }) async
    test('test createReturn', () async {
      // TODO
    });

    // Get order detail
    //
    //Future<Order> getOrder(int id, { String xTraceId }) async
    test('test getOrder', () async {
      // TODO
    });

    // List the authenticated user's orders
    //
    //Future<ListOrders200Response> listOrders({ String xTraceId, String status, int page, int perPage }) async
    test('test listOrders', () async {
      // TODO
    });

    // List return requests for an order
    //
    //Future<ListReturns200Response> listReturns(int id, { String xTraceId }) async
    test('test listReturns', () async {
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
