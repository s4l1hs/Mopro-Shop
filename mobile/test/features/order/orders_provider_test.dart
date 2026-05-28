import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';

OrderDto _order(int id) => OrderDto(
      id: id,
      userId: 1,
      status: OrderStatus.pendingPayment,
      totalMinor: 9900,
      currency: 'TRY',
      createdAt: DateTime(2026),
    );

class _FakeOrderRepo implements OrderRepository {
  _FakeOrderRepo({this.totalPages = 1});
  final int totalPages;

  @override
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20}) async =>
      OrderListResult(
        data: [_order(page * 10)],
        hasMore: page < totalPages,
        totalPages: totalPages,
        currentPage: page,
      );

  @override
  Future<OrderDto> getOrder(int id) async => _order(id);

  @override
  Future<void> cancelOrder({required int id, String reason = ''}) async {}
}

class _EmptyOrderRepo implements OrderRepository {
  @override
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20}) async =>
      OrderListResult(
        data: const [],
        hasMore: false,
        totalPages: 1,
        currentPage: page,
      );

  @override
  Future<OrderDto> getOrder(int id) async => _order(id);

  @override
  Future<void> cancelOrder({required int id, String reason = ''}) async {}
}

ProviderContainer _container(OrderRepository repo) => ProviderContainer(
      overrides: [orderRepositoryProvider.overrideWithValue(repo)],
    );

void main() {
  test('initial state is loading', () {
    final c = _container(_FakeOrderRepo());
    addTearDown(c.dispose);
    expect(c.read(ordersProvider).orders, isA<AsyncLoading<List<OrderDto>>>());
  });

  test('loads first page successfully', () async {
    final c = _container(_FakeOrderRepo());
    addTearDown(c.dispose);
    c.read(ordersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = c.read(ordersProvider);
    expect(state.orders.valueOrNull, isNotNull);
    expect(state.orders.valueOrNull!.length, 1);
    expect(state.currentPage, 1);
    expect(state.hasMore, false);
  });

  test('empty list is returned for no orders', () async {
    final c = _container(_EmptyOrderRepo());
    addTearDown(c.dispose);
    c.read(ordersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(ordersProvider).orders.valueOrNull, isEmpty);
  });

  test('loadNextPage appends to existing list', () async {
    final c = _container(_FakeOrderRepo(totalPages: 3));
    addTearDown(c.dispose);
    c.read(ordersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(ordersProvider).hasMore, true);

    await c.read(ordersProvider.notifier).loadNextPage();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = c.read(ordersProvider);
    expect(state.orders.valueOrNull!.length, 2);
    expect(state.currentPage, 2);
  });

  test('loadNextPage is no-op when no more pages', () async {
    final c = _container(_FakeOrderRepo());
    addTearDown(c.dispose);
    c.read(ordersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(ordersProvider).hasMore, false);

    final countBefore =
        c.read(ordersProvider).orders.valueOrNull!.length;
    await c.read(ordersProvider.notifier).loadNextPage();
    expect(c.read(ordersProvider).orders.valueOrNull!.length, countBefore);
  });

  test('refresh resets to page 1', () async {
    final c = _container(_FakeOrderRepo(totalPages: 2));
    addTearDown(c.dispose);
    c.read(ordersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(ordersProvider.notifier).loadNextPage();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await c.read(ordersProvider.notifier).refresh();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = c.read(ordersProvider);
    expect(state.currentPage, 1);
    expect(state.orders.valueOrNull!.length, 1);
  });
}
