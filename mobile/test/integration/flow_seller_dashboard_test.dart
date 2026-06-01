import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/router/app_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';
import 'package:mopro/features/seller/screens/seller_dashboard_screen.dart';
import 'package:mopro/features/seller/screens/seller_return_detail_screen.dart';
import 'package:mopro/features/seller/screens/seller_returns_inbox_screen.dart';
import 'package:mopro/features/seller/user_is_seller_provider.dart';
import 'package:mopro_api/mopro_api.dart';

import '../_support/test_harness.dart';

// Flow HH (seller return approval, full UI) + OO (role gating).

SellerBinding _binding() => SellerBinding(
      sellerId: 1,
      sellerSlug: 'acme-store',
      sellerName: 'Acme Store',
      role: SellerBindingRoleEnum.owner,
    );

SellerReturn _pending() => SellerReturn(
      id: 7,
      orderId: 5007,
      status: 'submitted',
      reason: 'damaged',
      description: 'Kutu ezik',
      refundAmountMinor: 12900,
      refundCurrency: 'TRY',
      createdAt: DateTime.utc(2026, 5, 2),
    );

class _FakeRepo extends SellerRepository {
  _FakeRepo() : super(Dio());
  int approveCalls = 0;
  @override
  Future<(List<SellerReturn>, bool)> listReturns({
    required String status,
    int limit = 20,
    int offset = 0,
  }) async =>
      (status == 'approved' ? const <SellerReturn>[] : [_pending()], false);
  @override
  Future<(List<SellerQuestion>, int, bool)> listQuestions({
    required bool unanswered,
    int page = 1,
    int pageSize = 20,
  }) async =>
      (const <SellerQuestion>[], 0, false);
  @override
  Future<void> approveReturn(int id) async => approveCalls++;
}

GoRouter _router() => GoRouter(
      initialLocation: '/seller/dashboard',
      routes: [
        GoRoute(
          path: '/seller/dashboard',
          builder: (_, __) => const SellerDashboardScreen(),
        ),
        GoRoute(
          path: '/seller/returns',
          builder: (_, state) => SellerReturnsInboxScreen(
            initialStatus: state.uri.queryParameters['status'] ?? 'submitted',
          ),
        ),
        GoRoute(
          path: '/seller/returns/:id',
          builder: (_, state) => SellerReturnDetailScreen(
            returnId: int.parse(state.pathParameters['id']!),
            initial: state.extra is SellerReturn
                ? state.extra! as SellerReturn
                : null,
          ),
        ),
        GoRoute(path: '/sellers/:slug', builder: (_, __) => const Scaffold()),
      ],
    );

void main() {
  setUpAll(initTestEnv);

  testWidgets('Flow HH: dashboard → returns → detail → approve → banner',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _FakeRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sellerRepositoryProvider.overrideWithValue(repo),
          currentSellerBindingProvider.overrideWithValue(_binding()),
        ],
        child: MaterialApp.router(theme: buildLightTheme(), routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();

    // Dashboard shows the pending-returns count (1) → go to returns.
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('seller.go_to_returns'));
    await tester.pumpAndSettle();

    // Inbox lists the pending return → open it.
    expect(find.byType(ListTile), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    // Detail → approve → confirm.
    await tester.tap(find.text('seller.approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('seller.approve').last);
    await tester.pumpAndSettle();

    expect(repo.approveCalls, 1);
    expect(find.text('seller.status_approved'), findsOneWidget);
  });

  test('Flow OO: role gate decisions (guest/non-seller redirect, seller passes)',
      () {
    // Non-seller / guest → redirected to / once role is known.
    expect(
      computeSellerRedirect(
        location: '/seller/dashboard',
        isSeller: false,
        sellerKnown: true,
      ),
      '/',
    );
    // Seller passes deep links through.
    expect(
      computeSellerRedirect(
        location: '/seller/returns/7',
        isSeller: true,
        sellerKnown: true,
      ),
      isNull,
    );
  });
}
