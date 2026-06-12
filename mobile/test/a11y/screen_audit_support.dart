import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/widgets/login_required_sheet.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/account/account_screen.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/account/security_screen.dart';
import 'package:mopro/features/account/widgets/account_shell.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/wallet/providers/cashback_plans_provider.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../_support/stub_unread_count.dart';

/// Shared screen-mount harness used by both the §3 baseline report and the §10
/// strict regression guard, so they audit identical configurations.

class FakeAuth extends AuthNotifier {
  FakeAuth(this._initial);
  final AuthState _initial;
  @override
  Future<AuthState> build() async => _initial;
}

class _FakeOrders extends OrdersNotifier {
  @override
  OrdersState build() => const OrdersState(orders: AsyncData([]));
}

class _FakeWallet extends WalletNotifier {
  @override
  WalletState build() => const WalletState();
}

class _FakeCashback extends CashbackPlansNotifier {
  @override
  CashbackPlansState build() => const CashbackPlansState(plans: AsyncData([]));
}

/// PD-10 mounted _RecentlyViewedRail on the PDP; the real notifier fires a raw
/// Dio GET (authed+consented here) whose timeout Timer leaks past teardown
/// ("Timer is still pending"). Empty data = rail renders zero space, no I/O.
class _FakeRecentlyViewed extends RecentlyViewedNotifier {
  @override
  AsyncValue<List<ProductSummary>> build() => const AsyncData([]);
}

Product _product() => Product(
      id: 123,
      sellerId: 1,
      sellerName: 'Acme',
      categoryId: 5,
      brand: 'Acme',
      status: ProductStatusEnum.active,
      attributes: const [],
      title: 'Test Ürünü',
      description: 'Kısa açıklama.',
      variants: [
        Variant(
          id: 1,
          sku: 'SKU1',
          color: 'Kırmızı',
          size: 'M',
          priceMinor: 12900,
          priceCurrency: 'TRY',
          stock: 10,
          imageUrls: const [],
        ),
        Variant(
          id: 2,
          sku: 'SKU2',
          color: 'Mavi',
          size: 'L',
          priceMinor: 13900,
          priceCurrency: 'TRY',
          stock: 5,
          imageUrls: const [],
        ),
      ],
      cashbackPreview:
          CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
      createdAt: DateTime.utc(2026),
    );

class _FakeCatalogApi extends CatalogApi {
  _FakeCatalogApi() : super(Dio());
  @override
  Future<Response<Product>> getProduct({
    required int id,
    String? destCity,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response(
        data: _product(),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

/// Configurations audited by §3/§10. Add new screens here.
const List<String> auditConfigs = [
  'account_authed_1440',
  'account_authed_375',
  'account_guest_1440',
  'account_shell_security_1440',
  'pdp_1440',
  'pdp_375',
  'login_dialog_1440',
  'login_sheet_375',
];

Future<void> installA11yMocks() async {
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
}

void _filterBenignErrors(WidgetTester tester) {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exceptionAsString();
    if (s.contains('overflowed') || s.contains('ListTile background color')) {
      return;
    }
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<void> pumpAuditConfig(WidgetTester tester, String config) async {
  _filterBenignErrors(tester);
  final size = config.endsWith('375')
      ? const Size(375, 900)
      : const Size(1440, 1000);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final prefs = await SharedPreferences.getInstance();
  final authed = !config.contains('guest');
  const user = CurrentUser(
    id: 1,
    displayName: 'Ada Lovelace',
    email: 'ada@example.com',
  );

  late final String location;
  late final Widget Function() child;
  switch (config) {
    case 'account_shell_security_1440':
      location = '/account/security';
      child = () => const AccountShell(child: SecurityScreen());
    case 'pdp_1440':
    case 'pdp_375':
      location = '/products/123';
      child = () => const ProductDetailScreen(productId: 123);
    case 'login_dialog_1440':
    case 'login_sheet_375':
      location = '/host';
      child = () => Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showLoginRequiredSheet(ctx, reason: 'r'),
                  child: const Text('open'),
                ),
              ),
            ),
          );
    default: // account_*
      location = '/account';
      child = () => const AccountScreen();
  }

  final router = GoRouter(
    initialLocation: location,
    routes: [GoRoute(path: location, builder: (_, __) => child())],
  );

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          stubUnreadCountOverride,
          authNotifierProvider.overrideWith(
            () => FakeAuth(
              authed
                  ? const AuthAuthenticated()
                  : const AuthUnauthenticated(),
            ),
          ),
          currentUserProvider.overrideWith(
            (ref) async => authed ? user : null,
          ),
          ordersProvider.overrideWith(_FakeOrders.new),
          walletProvider.overrideWith(_FakeWallet.new),
          cashbackPlansProvider.overrideWith(_FakeCashback.new),
          cartCountProvider.overrideWithValue(0),
          categoryTreeProvider.overrideWithValue(const AsyncData([])),
          catalogApiProvider.overrideWithValue(_FakeCatalogApi()),
          recentlyViewedProvider.overrideWith(_FakeRecentlyViewed.new),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  // Login presenters: open the modal so it is in the audited tree.
  if (config.startsWith('login_')) {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}
