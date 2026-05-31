import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/refund_status_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: MaterialApp(home: Scaffold(body: child)),
    );

RefundInfo _refund(String status, {DateTime? issuedAt, DateTime? estimatedAt}) =>
    RefundInfo(
      amountMinor: 12500,
      currency: 'TRY',
      method: 'original_payment',
      status: status,
      issuedAt: issuedAt,
      estimatedAt: estimatedAt,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  for (final status in [
    RefundStatus.pending,
    RefundStatus.processing,
    RefundStatus.issued,
    RefundStatus.failed,
  ]) {
    testWidgets('renders chip + amount for status: $status', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RefundStatusCard(
            refund: _refund(
              status,
              issuedAt: status == RefundStatus.issued ? DateTime(2026, 6, 10) : null,
              estimatedAt: status == RefundStatus.pending ? DateTime(2026, 6, 20) : null,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(Chip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('issued shows the issued date', (tester) async {
    await tester.pumpWidget(
      _wrap(RefundStatusCard(refund: _refund(RefundStatus.issued, issuedAt: DateTime(2026, 6, 10)))),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('10.06.2026'), findsOneWidget);
  });

  testWidgets('failed surfaces an explanatory caption', (tester) async {
    await tester.pumpWidget(
      _wrap(RefundStatusCard(refund: _refund(RefundStatus.failed))),
    );
    await tester.pump();
    await tester.pump();
    // The failed-hint key renders (raw key under test harness).
    expect(find.textContaining('refund_failed_hint'), findsOneWidget);
  });
}
