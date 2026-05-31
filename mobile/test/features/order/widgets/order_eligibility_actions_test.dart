import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/order_eligibility_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

OrderDto _order(OrderActions actions) => OrderDto(
      id: 1,
      userId: 1,
      status: OrderStatus.delivered,
      totalMinor: 9900,
      currency: 'TRY',
      createdAt: DateTime(2026),
      actions: actions,
    );

Future<void> _pump(WidgetTester tester, OrderActions actions) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: OrderEligibilityActions(order: _order(actions))),
        ),
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

  testWidgets('cancel only → only the cancel CTA', (tester) async {
    await _pump(tester, const OrderActions(canCancel: true));
    expect(find.text('order.cancel'), findsOneWidget);
    expect(find.text('returns.create_cta'), findsNothing);
  });

  testWidgets('return only → only the return CTA + helper text', (tester) async {
    await _pump(
      tester,
      OrderActions(canReturn: true, returnableUntil: DateTime(2026, 6, 30)),
    );
    expect(find.text('returns.create_cta'), findsOneWidget);
    expect(find.text('order.cancel'), findsNothing);
    expect(find.textContaining('returnable_until'), findsOneWidget);
  });

  testWidgets('both → both CTAs', (tester) async {
    await _pump(tester, const OrderActions(canCancel: true, canReturn: true));
    expect(find.text('order.cancel'), findsOneWidget);
    expect(find.text('returns.create_cta'), findsOneWidget);
  });

  testWidgets('neither → renders nothing', (tester) async {
    await _pump(tester, const OrderActions());
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget); // the SizedBox.shrink()
  });
}
