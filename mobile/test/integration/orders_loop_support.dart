import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/router/app_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_item_dto.dart';
import 'package:mopro/features/order/data/order_repository.dart';
import 'package:mopro/features/order/data/return_dto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthAuthenticated();
}

/// Stateful fake driving the whole orders loop: getOrder returns the current
/// order, cancelOrder flips it to cancelled + attaches a pending refund, and
/// createReturn records a return that listReturns then surfaces.
class FakeOrderLoopRepo with _Unused implements OrderRepository {
  FakeOrderLoopRepo(this._order);

  OrderDto _order;
  final List<ReturnListItemDto> _returns = [];
  int _nextReturnId = 500;

  @override
  Future<OrderDto> getOrder(int id) async => _order;

  @override
  Future<void> cancelOrder({
    required int id,
    String reason = '',
    String note = '',
  }) async {
    _order = _order.copyWith(
      status: OrderStatus.cancelled,
      updatedAt: DateTime(2026, 5, 2),
      actions: const OrderActions(),
      refund: const RefundInfo(
        amountMinor: 9900,
        currency: 'TRY',
        method: 'original_payment',
        status: RefundStatus.pending,
      ),
    );
  }

  @override
  Future<ReturnDetailDto> createReturn(CreateReturnRequest req) async {
    final id = _nextReturnId++;
    _returns.insert(
      0,
      ReturnListItemDto(
        id: id,
        orderId: req.orderId,
        status: ReturnLifecycle.pending,
        reason: req.reason,
        refundAmountMinor: 5000,
        refundCurrency: 'TRY',
        createdAt: DateTime(2026, 5, 2),
      ),
    );
    return ReturnDetailDto(
      id: id,
      orderId: req.orderId,
      status: ReturnLifecycle.pending,
      reason: req.reason,
      description: req.description,
      createdAt: DateTime(2026, 5, 2),
      items: req.items,
    );
  }

  @override
  Future<List<ReturnListItemDto>> listReturns({int limit = 20, int offset = 0}) async =>
      _returns;

  @override
  Future<ReturnDetailDto> getReturn(int id) async => ReturnDetailDto(
        id: id,
        orderId: _order.id,
        status: ReturnLifecycle.pending,
        reason: ReturnReason.damaged,
        createdAt: DateTime(2026, 5, 2),
      );
}

mixin _Unused implements OrderRepository {
  @override
  Future<OrderListResult> listOrders({int page = 1, int perPage = 20}) async =>
      const OrderListResult(data: [], hasMore: false, totalPages: 1, currentPage: 1);
}

OrderItemDto orderItem(int id, String title, int priceMinor) => OrderItemDto(
      id: id,
      orderId: 1,
      productId: id,
      variantId: id,
      title: title,
      priceMinor: priceMinor,
      qty: 1,
      commissionPctBps: 1000,
    );

OrderDto seedOrder({
  required String status,
  OrderActions? actions,
  RefundInfo? refund,
  List<OrderItemDto> items = const [],
}) =>
    OrderDto(
      id: 1,
      userId: 1,
      status: status,
      totalMinor: 9900,
      currency: 'TRY',
      createdAt: DateTime(2026, 5, 2),
      deliveredAt: status == OrderStatus.delivered ? DateTime(2026, 5, 2) : null,
      items: items,
      actions: actions,
      refund: refund,
    );

String currentLocation(WidgetTester tester) {
  final ctx = tester.element(find.byType(Navigator).first);
  return GoRouter.of(ctx).routeInformationProvider.value.uri.toString();
}

void goTo(WidgetTester tester, String path) {
  final ctx = tester.element(find.byType(Navigator).first);
  GoRouter.of(ctx).go(path);
}

Future<void> installOrdersLoopMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues(<String, Object>{});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    ..setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    )
    ..setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  await EasyLocalization.ensureInitialized();
  await initializeDateFormatting('tr_TR');
}

Future<void> pumpOrdersLoopApp(
  WidgetTester tester,
  FakeOrderLoopRepo repo, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authNotifierProvider.overrideWith(FakeAuth.new),
          orderRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith(
            (ref) async => const CurrentUser(
              id: 1,
              displayName: 'Ada',
              email: 'ada@example.com',
            ),
          ),
          cartCountProvider.overrideWithValue(0),
          categoryTreeProvider.overrideWithValue(const AsyncData([])),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: buildLightTheme(),
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void ignoreOverflow(WidgetTester tester) {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exceptionAsString();
    if (s.contains('overflowed') || s.contains('ListTile')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
}
