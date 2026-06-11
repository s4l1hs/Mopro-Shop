import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/cart/data/cart_totals_dto.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';
import 'package:mopro/features/checkout/data/checkout_repository.dart';
import 'package:mopro/features/checkout/data/checkout_response_dto.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';
import 'package:mopro_api/mopro_api.dart';

import '../_support/order_returns_stub.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeCartRepo implements CartRepository {
  CartDto _cart = const CartDto(
    id: 'c-1',
    userId: 1,
    lines: [],
    totalsBySeller: [],
    grandTotalMinor: 0,
    kdvIncludedMinor: 0,
  );

  @override
  Future<CartDto> getCart({String? coupon}) async => _cart;

  @override
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async {
    final line = CartLineDto(
      id: 'line-1',
      productId: productId,
      variantId: variantId,
      sellerId: 10,
      title: 'Test Product',
      priceMinor: 9900,
      qty: qty,
    );
    return _cart = CartDto(
      id: 'c-1',
      userId: 1,
      lines: [line],
      totalsBySeller: [
        SellerTotalDto(
          sellerId: 10,
          itemsMinor: line.lineTotalMinor,
          shippingMinor: 0,
          totalMinor: line.lineTotalMinor,
        ),
      ],
      grandTotalMinor: line.lineTotalMinor,
      kdvIncludedMinor: 0,
    );
  }

  @override
  Future<CartDto> updateQty({
    required String lineId,
    required int qty,
  }) async =>
      _cart;

  @override
  Future<void> removeLine({required String lineId}) async {
    _cart = const CartDto(
      id: 'c-1',
      userId: 1,
      lines: [],
      totalsBySeller: [],
      grandTotalMinor: 0,
      kdvIncludedMinor: 0,
    );
  }

  @override
  Future<void> clear() async {
    _cart = const CartDto(
      id: 'c-1',
      userId: 1,
      lines: [],
      totalsBySeller: [],
      grandTotalMinor: 0,
      kdvIncludedMinor: 0,
    );
  }
}

class _FakeCheckoutRepo implements CheckoutRepository {
  @override
  Future<CheckoutResponseDto> initiate({
    required String buyerName,
    required String buyerSurname,
    required String idempotencyKey,
    int? addressId,
    String returnUrl = 'mopro://checkout/result',
    String couponCode = '',
  }) async =>
      CheckoutResponseDto(
        sessionId: 'sess-1',
        sipayThreeDsUrl: 'https://ccpayment.sipay.com.tr/3DGate?token=abc',
        orders: [
          OrderDto(
            id: 101,
            userId: 1,
            status: OrderStatus.pendingPayment,
            totalMinor: 9900,
            currency: 'TRY',
            createdAt: DateTime(2026),
          ),
        ],
      );
}

Address _fakeAddress({int id = 5}) => Address(
      id: id,
      label: 'Ev',
      name: 'Test Kullanıcı',
      phone: '05551234567',
      city: 'İstanbul',
      district: 'Kadıköy',
      fullAddress: 'Test Sokak 1',
      isDefault: true,
    );

class _FakeOrderRepo with OrderReturnsStub implements OrderRepository {
  @override
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20}) async =>
      OrderListResult(
        data: [
          OrderDto(
            id: 101,
            userId: 1,
            status: OrderStatus.pendingPayment,
            totalMinor: 9900,
            currency: 'TRY',
            createdAt: DateTime(2026),
          ),
        ],
        hasMore: false,
        totalPages: 1,
        currentPage: 1,
      );

  @override
  Future<OrderDto> getOrder(int id) async => OrderDto(
        id: id,
        userId: 1,
        status: OrderStatus.pendingPayment,
        totalMinor: 9900,
        currency: 'TRY',
        createdAt: DateTime(2026),
      );

  @override
  Future<void> cancelOrder({
    required int id,
    String reason = '',
    String note = '',
  }) async {}
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        cartRepositoryProvider.overrideWithValue(_FakeCartRepo()),
        checkoutRepositoryProvider.overrideWithValue(_FakeCheckoutRepo()),
        orderRepositoryProvider.overrideWithValue(_FakeOrderRepo()),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('full purchase flow: add → checkout → order history', () async {
    // Step 1: Cart starts empty
    container.read(cartProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(cartProvider).cart.valueOrNull?.lines, isEmpty);

    // Step 2: Add item to cart
    await container.read(cartProvider.notifier).addItem(
          productId: 1,
          variantId: 1,
          qty: 1,
        );
    final cart = container.read(cartProvider).cart.valueOrNull!;
    expect(cart.lines.length, 1);
    expect(cart.grandTotalMinor, 9900);

    // Step 3: Select address and place order
    container
        .read(checkoutControllerProvider.notifier)
        .selectAddress(_fakeAddress());
    expect(container.read(checkoutControllerProvider).canProceed, true);

    await container.read(checkoutControllerProvider.notifier).placeOrder();
    final checkoutState = container.read(checkoutControllerProvider);
    expect(checkoutState.response, isNotNull);
    expect(checkoutState.response!.orders.length, 1);
    expect(checkoutState.response!.orders.first.id, 101);
    expect(checkoutState.response!.sipayThreeDsUrl, isNotEmpty);
    expect(checkoutState.response!.requires3ds, true);

    // Step 4: Verify order appears in history
    container.read(ordersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final orders = container.read(ordersProvider).orders.valueOrNull!;
    expect(orders.length, 1);
    expect(orders.first.id, 101);
    expect(orders.first.status, OrderStatus.pendingPayment);
  });

  test('cart count provider reflects line count', () async {
    container.read(cartProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container.read(cartProvider.notifier).addItem(
          productId: 1,
          variantId: 1,
          qty: 1,
        );

    final count = container.read(cartCountProvider);
    expect(count, 1);
  });

  test('checkout requires address before proceeding', () {
    expect(container.read(checkoutControllerProvider).canProceed, false);
    container
        .read(checkoutControllerProvider.notifier)
        .selectAddress(_fakeAddress(id: 3));
    expect(container.read(checkoutControllerProvider).canProceed, true);
  });
}
