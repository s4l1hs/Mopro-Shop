import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/wallet/widgets/month_dot.dart';
import 'package:mopro_api/mopro_api.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: ThemeData(useMaterial3: true), home: child);

void main() {
  testWidgets('renders without exception for paid', (tester) async {
    await tester.pumpWidget(
      _wrap(const MonthDot(status: CashbackPaymentStatusEnum.paid)),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('renders without exception for scheduled', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MonthDot(status: CashbackPaymentStatusEnum.scheduled),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without exception for failed', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MonthDot(status: CashbackPaymentStatusEnum.failed),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('paid dot uses primary colour', (tester) async {
    await tester.pumpWidget(
      _wrap(const MonthDot(status: CashbackPaymentStatusEnum.paid)),
    );
    final container =
        tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration?;
    expect(decoration?.shape, BoxShape.circle);
  });
}
