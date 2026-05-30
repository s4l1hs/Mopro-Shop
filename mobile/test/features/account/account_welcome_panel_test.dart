import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/account/widgets/account_welcome_panel.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/wallet/providers/cashback_plans_provider.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeOrders extends OrdersNotifier {
  @override
  OrdersState build() => const OrdersState(orders: AsyncData([]));
}

class _FakeWallet extends WalletNotifier {
  @override
  WalletState build() => const WalletState(); // loading → 0 via valueOrNull
}

class _FakeCashback extends CashbackPlansNotifier {
  @override
  CashbackPlansState build() => const CashbackPlansState(plans: AsyncData([]));
}

String _lastLocation = '/account';

Future<void> _pump(
  WidgetTester tester, {
  required CurrentUser? user,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});

  final router = GoRouter(
    initialLocation: '/account',
    observers: [],
    routes: [
      for (final p in const [
        '/account',
        '/',
        '/wallet',
        '/orders/:id',
        '/auth/login',
        '/auth/register',
      ])
        GoRoute(
          path: p,
          builder: (_, state) {
            _lastLocation = state.matchedLocation;
            return p == '/account'
                ? const Scaffold(body: AccountWelcomePanel())
                : const Scaffold(body: SizedBox.shrink());
          },
        ),
    ],
  );

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) async => user),
          ordersProvider.overrideWith(_FakeOrders.new),
          walletProvider.overrideWith(_FakeWallet.new),
          cashbackPlansProvider.overrideWith(_FakeCashback.new),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('authed welcome renders 3 quick-action cards with empty CTAs',
      (tester) async {
    await _pump(
      tester,
      user: const CurrentUser(id: 1, displayName: 'Ada Lovelace'),
    );
    expect(find.text('welcome.card_last_order'), findsOneWidget);
    expect(find.text('welcome.card_wallet'), findsOneWidget);
    expect(find.text('welcome.card_campaigns'), findsOneWidget);
    // Empty-data CTAs.
    expect(find.text('welcome.no_orders'), findsOneWidget);
    expect(find.text('welcome.start_shopping'), findsOneWidget);
    expect(find.text('welcome.wallet_cta'), findsOneWidget);
    expect(find.text('welcome.campaigns_cta'), findsOneWidget);
  });

  testWidgets('guest welcome renders 3 reason rows + login/register',
      (tester) async {
    await _pump(tester, user: null);
    expect(find.text('welcome.guest_title'), findsOneWidget);
    expect(find.text('welcome.reason_reco_title'), findsOneWidget);
    expect(find.text('welcome.reason_fav_title'), findsOneWidget);
    expect(find.text('welcome.reason_orders_title'), findsOneWidget);
    expect(find.text('auth.login'), findsOneWidget);
    expect(find.text('account.menu_register'), findsOneWidget);
  });

  testWidgets('wallet card CTA routes to /wallet', (tester) async {
    await _pump(
      tester,
      user: const CurrentUser(id: 1, displayName: 'Ada'),
    );
    await tester.tap(find.text('welcome.wallet_cta'));
    await tester.pumpAndSettle();
    expect(_lastLocation, '/wallet');
  });
}
