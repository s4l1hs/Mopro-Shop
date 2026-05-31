import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/presentation/order_return_flow_screen.dart';
import 'package:mopro/features/order/presentation/returns_list_screen.dart';
import 'package:mopro/features/order/widgets/order_eligibility_actions.dart';

import 'orders_loop_support.dart';

// ── Flow W — submit a return through the 4-step flow ─────────────────────────

void main() {
  setUpAll(installOrdersLoopMocks);

  testWidgets('Flow W: delivered order → return flow → confirmation → list',
      (tester) async {
    ignoreOverflow(tester);
    final repo = FakeOrderLoopRepo(
      seedOrder(
        status: OrderStatus.delivered,
        actions: const OrderActions(
          canReturn: true,
          returnableItems: [ReturnableItem(itemId: 10, maxQuantity: 2)],
        ),
        items: [orderItem(10, 'Ürün A', 5000)],
      ),
    );
    await pumpOrdersLoopApp(tester, repo);

    goTo(tester, '/orders/1');
    await tester.pumpAndSettle();
    expect(find.byType(OrderEligibilityActions), findsOneWidget);
    expect(find.text('returns.create_cta'), findsOneWidget);

    // Tap return → the full-screen flow opens at step 1.
    await tester.tap(find.text('returns.create_cta'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderReturnFlowScreen), findsOneWidget);
    expect(currentLocation(tester), contains('step=items'));

    // Select the returnable item, continue → reasons (step mirrored to URL).
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('returns.continue_cta'));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), contains('step=reasons'));

    // Pick a reason, continue → review.
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('returns.reason_damaged').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('returns.continue_cta'));
    await tester.pumpAndSettle();
    expect(currentLocation(tester), contains('step=review'));

    // Submit → confirmation with the return tracking number.
    await tester.tap(find.text('returns.submit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('returns.tracking_no'), findsOneWidget);

    // İadelerim → the new return is in the list.
    await tester.tap(find.text('returns.my_returns_cta'));
    await tester.pumpAndSettle();
    expect(find.byType(ReturnsListScreen), findsOneWidget);
    expect(find.textContaining('returns.return_no'), findsOneWidget);
  });
}
