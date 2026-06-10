@Tags(['golden'])
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';
import 'package:mopro/features/order/data/return_dto.dart';
import 'package:mopro/features/order/presentation/returns_list_screen.dart';
import 'package:mopro/features/order/widgets/order_status_chip.dart';
import 'package:mopro/features/order/widgets/refund_status_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/order_returns_stub.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

class _Repo with OrderReturnsStub implements OrderRepository {
  _Repo(this._returns);
  final List<ReturnListItemDto> _returns;
  @override
  Future<List<ReturnListItemDto>> listReturns({int limit = 20, int offset = 0}) async =>
      _returns;
  @override
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20}) async =>
      const OrderListResult(data: [], hasMore: false, totalPages: 1, currentPage: 1);
  @override
  Future<OrderDto> getOrder(int id) async => throw UnimplementedError();
  @override
  Future<void> cancelOrder({required int id, String reason = '', String note = ''}) async {}
}

RefundInfo _refund(String status) => RefundInfo(
      amountMinor: 12500,
      currency: 'TRY',
      method: 'original_payment',
      status: status,
      issuedAt: status == RefundStatus.issued ? DateTime(2026, 6, 10) : null,
      estimatedAt: status == RefundStatus.pending ? DateTime(2026, 6, 20) : null,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 420,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(Size(width, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  group('RefundStatusCard', () {
    for (final status in [
      RefundStatus.pending,
      RefundStatus.processing,
      RefundStatus.issued,
      RefundStatus.failed,
    ]) {
      testWidgets('refund_card_$status light', (tester) async {
        await _pump(
          tester,
          SizedBox(width: 360, child: RefundStatusCard(refund: _refund(status))),
        );
        await expectLater(
          find.byType(RefundStatusCard),
          matchesGoldenFile('goldens/refund_card_${status}_light.png'),
        );
      });
    }
  });

  group('OrderStatusTimeline post-purchase', () {
    for (final s in [OrderStatus.returnRequested, OrderStatus.refundIssued]) {
      testWidgets('timeline_$s light', (tester) async {
        await _pump(
          tester,
          SizedBox(
            width: 600,
            child: OrderStatusTimeline(status: s, at: DateTime(2026, 6, 10)),
          ),
          width: 640,
        );
        await expectLater(
          find.byType(OrderStatusTimeline),
          matchesGoldenFile('goldens/timeline_${s}_light.png'),
        );
      });
    }
  });

  group('ReturnsListScreen', () {
    testWidgets('returns_list_populated 1440 light', (tester) async {
      await _pump(
        tester,
        const ReturnsListScreen(),
        width: 1440,
        overrides: [
          orderRepositoryProvider.overrideWithValue(
            _Repo([
              ReturnListItemDto(
                id: 501,
                orderId: 101,
                status: ReturnLifecycle.pending,
                reason: ReturnReason.damaged,
                refundAmountMinor: 12500,
                refundCurrency: 'TRY',
                createdAt: DateTime(2026, 5, 2),
              ),
            ]),
          ),
        ],
      );
      await expectLater(
        find.byType(ReturnsListScreen),
        matchesGoldenFile('goldens/returns_list_populated_1440_light.png'),
      );
    });

    testWidgets('returns_list_empty 1440 light', (tester) async {
      await _pump(
        tester,
        const ReturnsListScreen(),
        width: 1440,
        overrides: [
          orderRepositoryProvider.overrideWithValue(_Repo(const [])),
        ],
      );
      await expectLater(
        find.byType(ReturnsListScreen),
        matchesGoldenFile('goldens/returns_list_empty_1440_light.png'),
      );
    });
  });
}