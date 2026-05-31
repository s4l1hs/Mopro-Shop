import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';
import 'package:mopro/features/order/data/return_dto.dart';
import 'package:mopro/features/order/presentation/return_detail_screen.dart';
import 'package:mopro/features/order/widgets/refund_status_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/order_returns_stub.dart';

class _Repo with OrderReturnsStub implements OrderRepository {
  _Repo(this._detail);
  final ReturnDetailDto _detail;

  @override
  Future<ReturnDetailDto> getReturn(int id) async => _detail;
  @override
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20}) async =>
      const OrderListResult(data: [], hasMore: false, totalPages: 1, currentPage: 1);
  @override
  Future<OrderDto> getOrder(int id) async => throw UnimplementedError();
  @override
  Future<void> cancelOrder({required int id, String reason = '', String note = ''}) async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders reason, items count, refund card, timeline state',
      (tester) async {
    final detail = ReturnDetailDto(
      id: 7,
      orderId: 100,
      status: ReturnLifecycle.refunded,
      reason: ReturnReason.damaged,
      createdAt: DateTime(2026, 5, 2),
      items: const [
        ReturnItemDto(orderItemId: 1, quantity: 2),
        ReturnItemDto(orderItemId: 2, quantity: 1),
      ],
      refund: const RefundInfo(
        amountMinor: 12500,
        currency: 'TRY',
        method: 'original_payment',
        status: RefundStatus.issued,
      ),
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('tr', 'TR')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr', 'TR'),
        child: ProviderScope(
          overrides: [orderRepositoryProvider.overrideWithValue(_Repo(detail))],
          child: const MaterialApp(home: ReturnDetailScreen(returnId: 7)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(RefundStatusCard), findsOneWidget);
    // refunded → timeline maps to refund_issued (payments icon).
    expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
    expect(find.textContaining('returns.original_order'), findsOneWidget);
  });

  test('timelineStatus maps lifecycle to post-purchase states', () {
    expect(
      ReturnDetailScreen.timelineStatus(ReturnLifecycle.pending),
      OrderStatus.returnRequested,
    );
    expect(
      ReturnDetailScreen.timelineStatus(ReturnLifecycle.approved),
      OrderStatus.returnApproved,
    );
    expect(
      ReturnDetailScreen.timelineStatus(ReturnLifecycle.rejected),
      OrderStatus.returnRejected,
    );
    expect(
      ReturnDetailScreen.timelineStatus(ReturnLifecycle.refunded),
      OrderStatus.refundIssued,
    );
  });
}
