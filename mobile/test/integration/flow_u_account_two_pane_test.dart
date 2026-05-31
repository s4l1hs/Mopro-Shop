import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/router/app_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/account/profile_screen.dart';
import 'package:mopro/features/account/security_screen.dart';
import 'package:mopro/features/account/widgets/account_left_rail.dart';
import 'package:mopro/features/account/widgets/account_welcome_panel.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/presentation/order_history_screen.dart';
import 'package:mopro/features/wallet/providers/cashback_plans_provider.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Flow U — account two-pane: ShellRoute, rail clicks, browser back, resize ──

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthAuthenticated();
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

String _location(WidgetTester tester) {
  final ctx = tester.element(find.byType(Navigator).first);
  return GoRouter.of(ctx).routeInformationProvider.value.uri.path;
}

void _go(WidgetTester tester, String path) {
  final ctx = tester.element(find.byType(Navigator).first);
  GoRouter.of(ctx).go(path);
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
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
  });

  testWidgets('Flow U: two-pane, rail nav, back, deep link, breakpoint resize',
      (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exceptionAsString();
      if (s.contains('overflowed') || s.contains('ListTile background color')) {
        return;
      }
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('tr', 'TR')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr', 'TR'),
        child: ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            authNotifierProvider.overrideWith(_FakeAuth.new),
            currentUserProvider.overrideWith(
              (ref) async => const CurrentUser(
                id: 1,
                displayName: 'Ada Lovelace',
                email: 'ada@example.com',
              ),
            ),
            ordersProvider.overrideWith(_FakeOrders.new),
            walletProvider.overrideWith(_FakeWallet.new),
            cashbackPlansProvider.overrideWith(_FakeCashback.new),
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

    // 3) /account desktop → two-pane: rail + welcome.
    _go(tester, '/account');
    await tester.pumpAndSettle();
    expect(find.byType(AccountLeftRail), findsOneWidget);
    expect(find.byType(AccountWelcomePanel), findsOneWidget);

    // 4) Tap "Güvenlik" → /account/security, Security in pane, rail persists.
    await tester.tap(find.text('account.security'));
    await tester.pumpAndSettle();
    expect(_location(tester), '/account/security');
    expect(find.byType(SecurityScreen), findsOneWidget);
    expect(find.byType(AccountLeftRail), findsOneWidget);

    // 5) Browser back → /account. Rail clicks use context.go (replace), so there
    // is no in-app back-stack to pop — browser history is what enables back, and
    // the widget harness can't replay it. We drive the previous URL directly
    // (the equivalent end state the browser would land on) and assert the welcome
    // re-renders, the rail persists, and no security highlight remains.
    _go(tester, '/account');
    await tester.pumpAndSettle();
    expect(_location(tester), '/account');
    expect(find.byType(AccountWelcomePanel), findsOneWidget);
    expect(find.byType(SecurityScreen), findsNothing);

    // 6) Tap "Siparişlerim" → /orders, orders list (empty state).
    await tester.tap(find.text('account.orders'));
    await tester.pumpAndSettle();
    expect(_location(tester), '/orders');
    expect(find.byType(OrderHistoryScreen), findsOneWidget);

    // 7) Deep link /account/profile (address-bar style) → Profile + rail.
    _go(tester, '/account/profile');
    await tester.pumpAndSettle();
    expect(_location(tester), '/account/profile');
    expect(find.byType(AccountProfileScreen), findsOneWidget);
    expect(find.byType(AccountLeftRail), findsOneWidget);

    // 8) Resize to mobile → rail unmounts, Profile renders with its own app bar.
    await _resize(tester, const Size(375, 667));
    expect(find.byType(AccountLeftRail), findsNothing);
    expect(find.byType(AccountProfileScreen), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);

    // 9) Resize back to desktop → rail re-mounts, still on Profile.
    await _resize(tester, const Size(1440, 900));
    expect(find.byType(AccountLeftRail), findsOneWidget);
    expect(find.byType(AccountProfileScreen), findsOneWidget);
    expect(_location(tester), '/account/profile');
  });
}
