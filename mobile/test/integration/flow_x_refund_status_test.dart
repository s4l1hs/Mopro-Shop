import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/refund_status_card.dart';

import 'orders_loop_support.dart';

// ── Flow X — view refund status on a previously-cancelled order ──────────────

void main() {
  setUpAll(installOrdersLoopMocks);

  testWidgets('Flow X: cancelled order shows the refund status card',
      (tester) async {
    ignoreOverflow(tester);
    final repo = FakeOrderLoopRepo(
      seedOrder(
        status: OrderStatus.cancelled,
        refund: const RefundInfo(
          amountMinor: 9900,
          currency: 'TRY',
          method: 'original_payment',
          status: RefundStatus.processing,
        ),
      ),
    );
    await pumpOrdersLoopApp(tester, repo);

    goTo(tester, '/orders/1');
    await tester.pumpAndSettle();

    expect(find.byType(RefundStatusCard), findsOneWidget);
    // processing → the processing chip label key renders.
    expect(find.textContaining('refund_status_processing'), findsOneWidget);
  });
}
