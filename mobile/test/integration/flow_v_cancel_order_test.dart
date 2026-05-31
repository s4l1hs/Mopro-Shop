import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/cancel_order_dialog.dart';
import 'package:mopro/features/order/widgets/order_eligibility_actions.dart';
import 'package:mopro/features/order/widgets/refund_status_card.dart';

import 'orders_loop_support.dart';

// ── Flow V — cancel a pre-shipment order ─────────────────────────────────────

void main() {
  setUpAll(installOrdersLoopMocks);

  testWidgets('Flow V: cancel a paid order → refund card appears',
      (tester) async {
    ignoreOverflow(tester);
    final repo = FakeOrderLoopRepo(
      seedOrder(
        status: OrderStatus.paid,
        actions: const OrderActions(canCancel: true),
      ),
    );
    await pumpOrdersLoopApp(tester, repo);

    goTo(tester, '/orders/1');
    await tester.pumpAndSettle();

    // Cancel CTA present, return CTA absent.
    expect(find.byType(OrderEligibilityActions), findsOneWidget);
    expect(find.text('order.cancel'), findsOneWidget);
    expect(find.text('returns.create_cta'), findsNothing);

    // Open the dialog.
    await tester.tap(find.text('order.cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(CancelOrderContent), findsOneWidget);

    // Submit is disabled until a reason is chosen.
    final submitBefore = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(CancelOrderContent),
        matching: find.byType(FilledButton),
      ),
    );
    expect(submitBefore.onPressed, isNull);

    // Pick a reason, then submit.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('returns.cancel_reason_changed_mind').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CancelOrderContent),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    // Dialog dismissed; order now cancelled with a refund card + success snack.
    expect(find.byType(CancelOrderContent), findsNothing);
    expect(find.byType(RefundStatusCard), findsOneWidget);
    expect(find.textContaining('cancel_success'), findsWidgets);
  });
}
