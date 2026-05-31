import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/application/return_flow_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';
import 'package:mopro/features/order/data/return_dto.dart';

import '../../_support/order_returns_stub.dart';

class _Repo with OrderReturnsStub implements OrderRepository {
  CreateReturnRequest? captured;

  @override
  Future<ReturnDetailDto> createReturn(CreateReturnRequest req) async {
    captured = req;
    return ReturnDetailDto(
      id: 99,
      orderId: req.orderId,
      status: ReturnLifecycle.pending,
      reason: req.reason,
      createdAt: DateTime(2026),
      items: req.items,
    );
  }

  @override
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20}) async =>
      const OrderListResult(data: [], hasMore: false, totalPages: 1, currentPage: 1);
  @override
  Future<OrderDto> getOrder(int id) async => throw UnimplementedError();
  @override
  Future<void> cancelOrder({required int id, String reason = '', String note = ''}) async {}
}

void main() {
  late ProviderContainer c;
  late _Repo repo;

  setUp(() {
    repo = _Repo();
    c = ProviderContainer(
      overrides: [orderRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
  });

  ReturnFlowNotifier notifier() => c.read(returnFlowProvider(1).notifier);
  ReturnFlowState state() => c.read(returnFlowProvider(1));

  test('toggle selects with qty 1; re-toggle deselects + clears reason/note', () {
    notifier().toggleItem(10);
    expect(state().selected[10], 1);
    notifier()
      ..setReason(10, ReturnReason.damaged)
      ..setNote(10, 'note')
      ..toggleItem(10);
    expect(state().selected.containsKey(10), isFalse);
    expect(state().reasons.containsKey(10), isFalse);
    expect(state().notes.containsKey(10), isFalse);
  });

  test('setQuantity ignores unselected + sub-1 values', () {
    notifier().setQuantity(10, 3); // not selected → ignored
    expect(state().selected.containsKey(10), isFalse);
    notifier()
      ..toggleItem(10)
      ..setQuantity(10, 0); // <1 → ignored
    expect(state().selected[10], 1);
    notifier().setQuantity(10, 2);
    expect(state().selected[10], 2);
  });

  test('allReasonsSet only true once every selected item has a reason', () {
    notifier()
      ..toggleItem(10)
      ..toggleItem(11);
    expect(state().allReasonsSet, isFalse);
    notifier().setReason(10, ReturnReason.damaged);
    expect(state().allReasonsSet, isFalse);
    notifier().setReason(11, ReturnReason.sizeIssue);
    expect(state().allReasonsSet, isTrue);
  });

  test('buildRequest carries items, first reason, and joined notes', () {
    notifier()
      ..toggleItem(10)
      ..setQuantity(10, 2)
      ..setReason(10, ReturnReason.damaged)
      ..setNote(10, 'crushed box');
    final req = notifier().buildRequest(1);
    expect(req.orderId, 1);
    expect(req.reason, ReturnReason.damaged);
    expect(req.items.single.orderItemId, 10);
    expect(req.items.single.quantity, 2);
    expect(req.description, 'crushed box');
  });

  test('submit posts and advances to confirm with the created id', () async {
    notifier()
      ..toggleItem(10)
      ..setReason(10, ReturnReason.damaged);
    await notifier().submit(1);
    expect(repo.captured, isNotNull);
    expect(state().createdReturnId, 99);
    expect(state().step, ReturnStep.confirm);
  });

  test('submit is a no-op without selection or reasons', () async {
    await notifier().submit(1);
    expect(repo.captured, isNull);
    notifier().toggleItem(10); // selected but no reason
    await notifier().submit(1);
    expect(repo.captured, isNull);
  });
}
