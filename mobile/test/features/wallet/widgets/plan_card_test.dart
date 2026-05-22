import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/wallet/widgets/plan_card.dart';
import 'package:mopro_api/mopro_api.dart';

CashbackPlan _plan({String? longTitle}) => CashbackPlan(
      id: 1,
      orderId: 100,
      productId: 0,
      productTitle: longTitle ??
          'Test Product with a short title',
      monthlyAmountMinor: 5000,
      currency: 'TRY_COIN',
      status: CashbackPlanStatusEnum.active,
      startDate: DateTime(2026),
      referenceInterestRateBps: 5000,
      createdAt: DateTime(2026),
    );

Widget _wrap(CashbackPlan plan, {VoidCallback? onTap}) =>
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: PlanCard(plan: plan, onTap: onTap ?? () {}),
      ),
    );

void main() {
  testWidgets('renders product title', (tester) async {
    await tester.pumpWidget(_wrap(_plan()));
    expect(
      find.text('Test Product with a short title'),
      findsOneWidget,
    );
  });

  testWidgets('fires onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(_plan(), onTap: () => tapped = true),
    );
    await tester.tap(find.byType(InkWell));
    expect(tapped, isTrue);
  });

  testWidgets('long title is clipped with ellipsis', (tester) async {
    final plan = _plan(
      longTitle:
          'A very long product title that should overflow the card',
    );
    await tester.pumpWidget(_wrap(plan));
    expect(tester.takeException(), isNull);
    // Text widget with overflow ellipsis exists
    final texts = tester.widgetList<Text>(find.byType(Text));
    final hasOverflow = texts.any(
      (t) => t.overflow == TextOverflow.ellipsis,
    );
    expect(hasOverflow, isTrue);
  });

  testWidgets('shows placeholder when imageUrl is null', (tester) async {
    await tester.pumpWidget(_wrap(_plan()));
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
  });
}
