import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mopro/features/wallet/widgets/month_dot.dart';
import 'package:mopro/features/wallet/widgets/plan_timeline_row.dart';
import 'package:mopro_api/mopro_api.dart';

CashbackPayment _payment(CashbackPaymentStatusEnum status) =>
    CashbackPayment(
      id: 1,
      planId: 10,
      periodYyyymm: '202601',
      amountMinor: 5000,
      currency: 'TRY_COIN',
      status: status,
      paidAt: status == CashbackPaymentStatusEnum.paid
          ? DateTime(2026, 1, 15)
          : null,
    );

Widget _wrap(CashbackPayment payment) => MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: PlanTimelineRow(
          payment: payment,
          currency: 'TRY_COIN',
        ),
      ),
    );

void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));

  testWidgets('renders MonthDot for each status', (tester) async {
    for (final status in CashbackPaymentStatusEnum.values) {
      await tester.pumpWidget(_wrap(_payment(status)));
      expect(find.byType(MonthDot), findsOneWidget);
    }
  });

  testWidgets('renders Turkish month label for 202601', (tester) async {
    await tester.pumpWidget(
      _wrap(_payment(CashbackPaymentStatusEnum.paid)),
    );
    expect(find.text('Ocak 2026'), findsOneWidget);
  });

  testWidgets('renders without exception for all statuses',
      (tester) async {
    for (final status in CashbackPaymentStatusEnum.values) {
      await tester.pumpWidget(_wrap(_payment(status)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
