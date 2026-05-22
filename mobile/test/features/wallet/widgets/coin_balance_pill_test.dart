import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/wallet/widgets/coin_balance_pill.dart';

Widget _wrap({required VoidCallback onTap}) => MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: CoinBalancePill(
          amountMinor: 50000,
          currency: 'TRY_COIN',
          onTap: onTap,
        ),
      ),
    );

void main() {
  testWidgets('renders without exception', (tester) async {
    await tester.pumpWidget(_wrap(onTap: () {}));
    expect(tester.takeException(), isNull);
  });

  testWidgets('displays formatted coin amount', (tester) async {
    await tester.pumpWidget(_wrap(onTap: () {}));
    // "500,00 MC" — exact text depends on locale but contains "MC"
    expect(find.textContaining('MC'), findsOneWidget);
  });

  testWidgets('fires onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(onTap: () => tapped = true));
    await tester.tap(find.byType(InkWell));
    expect(tapped, isTrue);
  });
}
