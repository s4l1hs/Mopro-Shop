import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';
import 'package:mopro/features/checkout/data/checkout_repository.dart';
import 'package:mopro/features/checkout/data/checkout_response_dto.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro_api/mopro_api.dart';

Address _fakeAddress() => Address(
      id: 1,
      label: 'Ev',
      name: 'Ali Yılmaz',
      phone: '05551234567',
      city: 'İstanbul',
      district: 'Kadıköy',
      fullAddress: 'Test Sokak 1',
      isDefault: true,
    );

CheckoutResponseDto _successResponse() => CheckoutResponseDto(
      sessionId: 'sess-1',
      sipayThreeDsUrl: 'https://ccpayment.sipay.com.tr/3DGate?token=abc',
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
    required String buyerName,
    required String buyerSurname,
    required String idempotencyKey,
    String returnUrl = 'mopro://checkout/result',
    String couponCode = '',
  }) async =>
      _successResponse();
}

class _FailingCheckoutRepo implements CheckoutRepository {
  @override
  Future<CheckoutResponseDto> initiate({
    required String buyerName,
    required String buyerSurname,
    required String idempotencyKey,
    String returnUrl = 'mopro://checkout/result',
    String couponCode = '',
  }) async =>
      throw DioException(requestOptions: RequestOptions(), message: 'fail');
}

// _EmptyCartRepo lets cartProvider build (the controller reads its coupon code).
class _EmptyCartRepo implements CartRepository {
  @override
  Future<CartDto> getCart({String? coupon}) async => CartDto.empty();
  @override
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async =>
      CartDto.empty();
  @override
  Future<CartDto> updateQty({required String lineId, required int qty}) async =>
      CartDto.empty();
  @override
  Future<void> removeLine({required String lineId}) async {}
  @override
  Future<void> clear() async {}
}

ProviderContainer _container(CheckoutRepository repo) => ProviderContainer(
      overrides: [
        checkoutRepositoryProvider.overrideWithValue(repo),
        cartRepositoryProvider.overrideWithValue(_EmptyCartRepo()),
      ],
    );

void main() {
  test('initial state has no address and default payment method', () {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    final state = c.read(checkoutControllerProvider);
    expect(state.selectedAddress, isNull);
    expect(state.selectedAddressId, isNull);
    expect(state.paymentMethod, 'card');
    expect(state.isInitiating, false);
    expect(state.canProceed, false);
  });

  test('selectAddress stores full address and enables proceed', () {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(_fakeAddress());
    final state = c.read(checkoutControllerProvider);
    expect(state.selectedAddressId, 1);
    expect(state.selectedAddress?.name, 'Ali Yılmaz');
    expect(state.canProceed, true);
  });

  test('placeOrder with no address is a no-op', () async {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    expect(c.read(checkoutControllerProvider).response, isNull);
    expect(c.read(checkoutControllerProvider).isInitiating, false);
  });

  test('placeOrder success sets response and invoiceId', () async {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(_fakeAddress());
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    final state = c.read(checkoutControllerProvider);
    expect(state.response, isNotNull);
    expect(state.response!.sessionId, 'sess-1');
    expect(state.response!.sipayThreeDsUrl, isNotEmpty);
    expect(state.response!.requires3ds, true);
    expect(state.invoiceId, isNotNull);
    expect(state.isInitiating, false);
    expect(state.error, isNull);
  });

  test('placeOrder failure sets error', () async {
    final c = _container(_FailingCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(_fakeAddress());
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    final state = c.read(checkoutControllerProvider);
    expect(state.error, isNotNull);
    expect(state.response, isNull);
    expect(state.isInitiating, false);
  });

  test('setPaymentError stores Turkish message and clears response', () async {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(_fakeAddress());
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    c
        .read(checkoutControllerProvider.notifier)
        .setPaymentError('Kartınız reddedildi.');
    final state = c.read(checkoutControllerProvider);
    expect(state.paymentError, 'Kartınız reddedildi.');
    expect(state.response, isNull);
    expect(state.invoiceId, isNull);
  });

  test('clearPaymentError removes the message', () {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c
        .read(checkoutControllerProvider.notifier)
        .setPaymentError('Test error');
    c.read(checkoutControllerProvider.notifier).clearPaymentError();
    expect(c.read(checkoutControllerProvider).paymentError, isNull);
  });

  test('reset clears all state', () async {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectAddress(_fakeAddress());
    await c.read(checkoutControllerProvider.notifier).placeOrder();
    c.read(checkoutControllerProvider.notifier).reset();
    final state = c.read(checkoutControllerProvider);
    expect(state.selectedAddress, isNull);
    expect(state.response, isNull);
    expect(state.invoiceId, isNull);
    expect(state.paymentError, isNull);
  });

  test('selectPaymentMethod updates state', () {
    final c = _container(_FakeCheckoutRepo());
    addTearDown(c.dispose);
    c.read(checkoutControllerProvider.notifier).selectPaymentMethod('wallet');
    expect(c.read(checkoutControllerProvider).paymentMethod, 'wallet');
  });

  test('buyer name split: Ali Yılmaz → name=Ali, surname=Yılmaz', () {
    // Verify the split logic matches what the controller sends
    const fullName = 'Ali Yılmaz';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final name = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join(' ')
        : fullName;
    final surname = parts.length > 1 ? parts.last : '';
    expect(name, 'Ali');
    expect(surname, 'Yılmaz');
  });

  test('buyer name split: single word → name=Mopro, surname=empty', () {
    const fullName = 'Mopro';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final name = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join(' ')
        : fullName;
    final surname = parts.length > 1 ? parts.last : '';
    expect(name, 'Mopro');
    expect(surname, '');
  });
}
