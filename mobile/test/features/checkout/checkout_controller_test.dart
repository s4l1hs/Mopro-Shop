import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';
import 'package:mopro/features/checkout/data/checkout_repository.dart';
import 'package:mopro/features/checkout/data/checkout_response_dto.dart';
import 'package:mopro/features/order/data/order_dto.dart';

CheckoutResponseDto _successResponse() => CheckoutResponseDto(
      sessionId: 'sess-1',
      threeDsHtml: '<html>3DS</html>',
      orders: [
        OrderDto(
          id: 100,
          userId: 1,
          status: OrderStatus.pendingPayment,
          totalMinor: 9900,
          currency: 'TRY',
          createdAt: DateTime(2026),
        ),
      ],
    );

class _FakeCheckoutRepo implements CheckoutRepository {
  @override
  Future<CheckoutResponseDto> initiate({
    required int addressId,
    required String paymentMethod,
    required String idempotencyKey,
  }) async =>
      _successResponse();
}

class _FailingCheckoutRepo implements CheckoutRepository {
  @override
  Future<CheckoutResponseDto> initiate({
    required int addressId,
    required String paymentMethod,
    required String idempotencyKey,
  }) async =>
      throw DioException(requestOptions: RequestOptions(), message: 'fail');
}

ProviderContainer _container(CheckoutRepository repo) => ProviderContainer(
      overrides: [checkoutRepositoryProvider.overrideWithValue(repo)],
    );

void main() {
  test('initial state has no address and default payment method', () {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    final state = c.read(checkoutControllerProvider);
    expect(state.selectedAddressId, isNull);
    expect(state.paymentMethod, 'card');
    expect(state.isInitiating, false);
    expect(state.canProceed, false);
  });

  test('selectAddress enables proceed', () {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(5);
    final state = c.read(checkoutControllerProvider);
    expect(state.selectedAddressId, 5);
    expect(state.canProceed, true);
  });

  test('placeOrder with no address is a no-op', () async {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    expect(c.read(checkoutControllerProvider).response, isNull);
    expect(c.read(checkoutControllerProvider).isInitiating, false);
  });

  test('placeOrder success sets response', () async {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(1);
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    final state = c.read(checkoutControllerProvider);
    expect(state.response, isNotNull);
    expect(state.response!.sessionId, 'sess-1');
    expect(state.response!.orders.length, 1);
    expect(state.isInitiating, false);
    expect(state.error, isNull);
  });

  test('placeOrder success with 3DS HTML sets requires3ds', () async {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(1);
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    expect(c.read(checkoutControllerProvider).response!.requires3ds, true);
  });

  test('placeOrder failure sets error', () async {
    final c = _container(_FailingCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(1);
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    final state = c.read(checkoutControllerProvider);
    expect(state.error, isNotNull);
    expect(state.response, isNull);
    expect(state.isInitiating, false);
  });

  test('reset clears state', () async {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(1);
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    c.read(checkoutControllerProvider.notifier).reset();
    final state = c.read(checkoutControllerProvider);
    expect(state.selectedAddressId, isNull);
    expect(state.response, isNull);
  });

  test('selectPaymentMethod updates state', () {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectPaymentMethod('wallet');
    expect(c.read(checkoutControllerProvider).paymentMethod, 'wallet');
  });
}
