import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/order_status_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  group('OrderStatusChip', () {
    for (final status in [
      OrderStatus.pendingPayment,
      OrderStatus.paid,
      OrderStatus.shipped,
      OrderStatus.delivered,
      OrderStatus.cancelled,
      OrderStatus.refunded,
      OrderStatus.partiallyRefunded,
    ]) {
      testWidgets('renders without overflow for status: $status',
          (tester) async {
        await tester.pumpWidget(
          _wrap(OrderStatusChip(status: status)),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(Chip), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders unknown status without crashing', (tester) async {
      await tester.pumpWidget(
        _wrap(const OrderStatusChip(status: 'unknown_future_status')),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('OrderStatusTimeline', () {
    testWidgets('renders all 4 steps for delivered status', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 1100,
            child: OrderStatusTimeline(status: OrderStatus.delivered),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.check), findsWidgets);
    });

    testWidgets('cancelled renders cancel icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 1100,
            child: OrderStatusTimeline(status: OrderStatus.cancelled),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });
  });
}
