import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';
import 'package:mopro/features/seller/screens/seller_return_detail_screen.dart';
import 'package:mopro/features/seller/screens/seller_returns_inbox_screen.dart';

import '../../_support/test_harness.dart';

SellerReturn _ret(int id, {String status = 'submitted'}) => SellerReturn(
      id: id,
      orderId: 5000 + id,
      status: status,
      reason: 'damaged',
      description: 'Kutu ezilmiş',
      refundAmountMinor: 12900,
      refundCurrency: 'TRY',
      createdAt: DateTime.utc(2026, 5, 2),
    );

class _FakeRepo extends SellerRepository {
  _FakeRepo({this.returns = const []}) : super(Dio());
  final List<SellerReturn> returns;
  int approveCalls = 0;
  int rejectCalls = 0;
  String? lastRejectCode;

  @override
  Future<(List<SellerReturn>, bool)> listReturns({
    required String status,
    int limit = 20,
    int offset = 0,
  }) async {
    final filtered = status.isEmpty
        ? returns
        : returns.where((r) => r.status == status).toList();
    return (filtered, false);
  }

  @override
  Future<void> approveReturn(int id) async => approveCalls++;

  @override
  Future<void> rejectReturn(int id, String reasonCode, String? note) async {
    rejectCalls++;
    lastRejectCode = reasonCode;
  }
}

Future<void> _pump(WidgetTester tester, Widget child, _FakeRepo repo) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sellerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: buildLightTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('inbox renders a card per return', (tester) async {
    await _pump(
      tester,
      const SellerReturnsInboxScreen(),
      _FakeRepo(returns: [_ret(1), _ret(2)]),
    );
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('approve flow: confirm dialog → repo.approve → approved banner',
      (tester) async {
    final repo = _FakeRepo();
    await _pump(
      tester,
      SellerReturnDetailScreen(returnId: 1, initial: _ret(1)),
      repo,
    );
    await tester.tap(find.text('seller.approve'));
    await tester.pumpAndSettle();
    // Confirm dialog → tap the approve action inside it.
    expect(find.text('seller.approve_confirm_title'), findsOneWidget);
    await tester.tap(find.text('seller.approve').last);
    await tester.pumpAndSettle();
    expect(repo.approveCalls, 1);
    // Action buttons replaced by the approved status banner.
    expect(find.text('seller.status_approved'), findsOneWidget);
  });

  testWidgets('reject flow: sheet → reason → repo.reject', (tester) async {
    final repo = _FakeRepo();
    await _pump(
      tester,
      SellerReturnDetailScreen(returnId: 1, initial: _ret(1)),
      repo,
    );
    await tester.tap(find.text('seller.reject'));
    await tester.pumpAndSettle();
    expect(find.text('seller.reject_title'), findsOneWidget);
    // Submit with the default reason.
    await tester.tap(find.text('seller.reject').last);
    await tester.pumpAndSettle();
    expect(repo.rejectCalls, 1);
    expect(repo.lastRejectCode, 'not_as_returned');
    expect(find.text('seller.status_rejected'), findsOneWidget);
  });

  testWidgets('approved return shows banner, no action buttons', (tester) async {
    await _pump(
      tester,
      SellerReturnDetailScreen(returnId: 1, initial: _ret(1, status: 'approved')),
      _FakeRepo(),
    );
    expect(find.text('seller.approve'), findsNothing);
    expect(find.text('seller.reject'), findsNothing);
  });
}
