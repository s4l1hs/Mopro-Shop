import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/cart/data/cart_totals_dto.dart';

CartDto _emptyCart() => CartDto(
      id: 'c-1',
      userId: 1,
      lines: const [],
      totalsBySeller: const [],
      grandTotalMinor: 0,
      kdvIncludedMinor: 0,
    );

CartLineDto _line(String id) => CartLineDto(
      id: id,
      productId: 1,
      variantId: 1,
      sellerId: 10,
      title: 'Test Product',
      priceMinor: 9900,
      qty: 1,
    );

CartDto _cartWith(List<CartLineDto> lines) => CartDto(
      id: 'c-1',
      userId: 1,
      lines: lines,
      totalsBySeller: [
        SellerTotalDto(
          sellerId: 10,
          itemsMinor: lines.fold(0, (s, l) => s + l.lineTotalMinor),
          shippingMinor: 0,
          totalMinor: lines.fold(0, (s, l) => s + l.lineTotalMinor),
        ),
      ],
      grandTotalMinor: lines.fold(0, (s, l) => s + l.lineTotalMinor),
      kdvIncludedMinor: 0,
    );

class _FakeCartRepo implements CartRepository {
  CartDto _cart = _emptyCart();

  @override
  Future<CartDto> getCart() async => _cart;

  @override
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async {
    final line = _line('line-1');
    _cart = _cartWith([line]);
    return _cart;
  }

  @override
  Future<CartDto> updateQty({
    required String lineId,
    required int qty,
  }) async {
    _cart = _cartWith([
      CartLineDto(
        id: lineId,
        productId: 1,
        variantId: 1,
        sellerId: 10,
        title: 'Test Product',
        priceMinor: 9900,
        qty: qty,
      ),
    ]);
    return _cart;
  }

  @override
  Future<void> removeLine({required String lineId}) async {
    _cart = _emptyCart();
  }

  @override
  Future<void> clear() async {
    _cart = _emptyCart();
  }
}

class _ThrowingCartRepo implements CartRepository {
  @override
  Future<CartDto> getCart() async =>
      throw DioException(requestOptions: RequestOptions(), message: 'timeout');

  @override
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async =>
      throw DioException(requestOptions: RequestOptions());

  @override
  Future<CartDto> updateQty({
    required String lineId,
    required int qty,
  }) async =>
      throw DioException(requestOptions: RequestOptions());

  @override
  Future<void> removeLine({required String lineId}) async =>
      throw DioException(requestOptions: RequestOptions());

  @override
  Future<void> clear() async =>
      throw DioException(requestOptions: RequestOptions());
}

ProviderContainer _container(CartRepository repo) => ProviderContainer(
      overrides: [cartRepositoryProvider.overrideWithValue(repo)],
    );

void main() {
  test('initial state is loading', () {
    final c = _container(_FakeCartRepo());
    addTearDown(c.dispose);
    expect(c.read(cartProvider).cart, isA<AsyncLoading<CartDto>>());
  });

  test('loads cart successfully', () async {
    final c = _container(_FakeCartRepo());
    addTearDown(c.dispose);
    c.read(cartProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = c.read(cartProvider);
    expect(state.cart.valueOrNull, isNotNull);
    expect(state.cart.valueOrNull?.lines, isEmpty);
    expect(state.isMutating, false);
  });

  test('error state on load failure', () async {
    final c = _container(_ThrowingCartRepo());
    addTearDown(c.dispose);
    c.read(cartProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = c.read(cartProvider);
    expect(state.cart, isA<AsyncError<CartDto>>());
  });

  test('addItem updates cart lines', () async {
    final c = _container(_FakeCartRepo());
    addTearDown(c.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(cartProvider.notifier).addItem(
          productId: 1,
          variantId: 1,
          qty: 1,
        );
    final state = c.read(cartProvider);
    expect(state.cart.valueOrNull?.lines.length, 1);
    expect(state.isMutating, false);
  });

  test('clear empties the cart', () async {
    final c = _container(_FakeCartRepo());
    addTearDown(c.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(cartProvider.notifier).addItem(
          productId: 1,
          variantId: 1,
          qty: 1,
        );
    await c.read(cartProvider.notifier).clear();
    final state = c.read(cartProvider);
    expect(state.cart.valueOrNull?.lines, isEmpty);
  });

  test('updateQty changes quantity', () async {
    final repo = _FakeCartRepo();
    await repo.addItem(productId: 1, variantId: 1, qty: 1);
    final c = ProviderContainer(
      overrides: [cartRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(cartProvider.notifier).updateQty(lineId: 'line-1', qty: 3);
    final state = c.read(cartProvider);
    expect(state.cart.valueOrNull?.lines.first.qty, 3);
  });
}
