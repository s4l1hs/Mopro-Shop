import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';
import 'package:mopro/features/order/data/return_dto.dart';
import 'package:mopro/features/order/presentation/returns_list_screen.dart';
import 'package:mopro/features/order/widgets/return_status_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/order_returns_stub.dart';

class _Repo with OrderReturnsStub implements OrderRepository {
  _Repo(this._returns);
  final List<ReturnListItemDto> _returns;

  @override
  Future<List<ReturnListItemDto>> listReturns({int limit = 20, int offset = 0}) async =>
      _returns;
  @override
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20}) async =>
      const OrderListResult(data: [], hasMore: false, totalPages: 1, currentPage: 1);
  @override
  Future<OrderDto> getOrder(int id) async => throw UnimplementedError();
  @override
  Future<void> cancelOrder({required int id, String reason = '', String note = ''}) async {}
}

ReturnListItemDto _item(int id, {String status = ReturnLifecycle.pending}) =>
    ReturnListItemDto(
      id: id,
      orderId: 100 + id,
      status: status,
      reason: ReturnReason.damaged,
      refundAmountMinor: 12500,
      refundCurrency: 'TRY',
      createdAt: DateTime(2026, 5, 2),
    );

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [orderRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: ReturnsListScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('populated list renders one card per return', (tester) async {
    await _pump(tester, _Repo([_item(1), _item(2)]));
    expect(find.byType(ReturnStatusChip), findsNWidgets(2));
    expect(find.textContaining('returns.return_no'), findsNWidgets(2));
  });

  testWidgets('empty list renders empty state + go-orders CTA', (tester) async {
    await _pump(tester, _Repo(const []));
    expect(find.textContaining('returns.empty'), findsOneWidget);
    expect(find.textContaining('returns.go_orders'), findsOneWidget);
  });

  // RT-06 — client-side status filter.
  testWidgets('single-status list hides the filter bar', (tester) async {
    await _pump(tester, _Repo([_item(1), _item(2)]));
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('mixed-status list shows All + per-status filter chips',
      (tester) async {
    await _pump(
      tester,
      _Repo([
        _item(1),
        _item(2, status: ReturnLifecycle.approved),
      ]),
    );
    // "All" + the two present statuses (pending, approved).
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    expect(find.text('returns.filter_all'), findsOneWidget);
  });

  testWidgets('tapping a status chip filters the list to that status',
      (tester) async {
    await _pump(
      tester,
      _Repo([
        _item(1),
        _item(2, status: ReturnLifecycle.approved),
      ]),
    );
    // Two cards before filtering. The card status chip is a ReturnStatusChip;
    // the filter chips are ChoiceChips — distinct types, so counts don't clash.
    expect(find.byType(ReturnStatusChip), findsNWidgets(2));

    // Tap the "approved" filter chip (label is the keyed status string in
    // test). The chip sits in a horizontal bar — ensure it is on-screen first.
    final approvedChip =
        find.widgetWithText(ChoiceChip, 'returns.status_approved');
    await tester.ensureVisible(approvedChip);
    await tester.pumpAndSettle();
    await tester.tap(approvedChip);
    await tester.pumpAndSettle();

    // Only the approved return remains visible.
    expect(find.byType(ReturnStatusChip), findsOneWidget);

    // Re-selecting "All" restores both.
    final allChip = find.widgetWithText(ChoiceChip, 'returns.filter_all');
    await tester.ensureVisible(allChip);
    await tester.pumpAndSettle();
    await tester.tap(allChip);
    await tester.pumpAndSettle();
    expect(find.byType(ReturnStatusChip), findsNWidgets(2));
  });
}
