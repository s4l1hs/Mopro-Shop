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
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/account/account_screen.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/account/profile_screen.dart';
import 'package:mopro/features/account/security_screen.dart';
import 'package:mopro/features/account/widgets/account_shell.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/wallet/providers/cashback_plans_provider.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._initial);
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

const _user = CurrentUser(
  id: 1,
  displayName: 'Ada Lovelace',
  email: 'ada@example.com',
);

Future<void> _pump(
  WidgetTester tester, {
  required String location,
  required Widget Function() child,
  required double width,
  required Brightness brightness,
  CurrentUser? user = _user,
}) async {
  // SecurityScreen wraps ListTiles in a ColoredBox, tripping a pre-existing
  // benign Flutter debug hint; filter just that one (same as theme_picker_test).
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('ListTile background color')) {
      return;
    }
    originalOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalOnError);

  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: location, builder: (_, __) => child()),
    ],
  );

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWith((ref) async => user),
          authNotifierProvider.overrideWith(
            () => _FakeAuth(
              user == null
                  ? const AuthUnauthenticated()
                  : const AuthAuthenticated(),
            ),
          ),
          ordersProvider.overrideWith(_FakeOrders.new),
          walletProvider.overrideWith(_FakeWallet.new),
          cashbackPlansProvider.overrideWith(_FakeCashback.new),
          cartCountProvider.overrideWithValue(0),
          categoryTreeProvider.overrideWithValue(const AsyncData([])),
        ],
        child: MaterialApp.router(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          routerConfig: router,
        ),
      ),
    ),
  );
  // Not pumpAndSettle: SecurityScreen shows a perpetual loading spinner (no
  // network in tests). Fixed-duration pumps resolve the async providers and
  // give a deterministic frame.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => Directory.systemTemp.path,
      )
      // SecurityScreen's init fires a dio call whose auth interceptor reads the
      // token from secure storage; stub it so goldens don't throw.
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => call.method == 'readAll' ? <String, String>{} : null,
      );
    await EasyLocalization.ensureInitialized();
  });

  for (final width in [1024.0, 1440.0]) {
    final w = width.toInt();

    // Welcome panel (authed) — light + dark.
    for (final brightness in Brightness.values) {
      final b = brightness == Brightness.dark ? 'dark' : 'light';
      testWidgets('account welcome authed $w $b', (tester) async {
        await _pump(
          tester,
          location: '/account',
          child: () => const AccountScreen(),
          width: width,
          brightness: brightness,
        );
        await expectLater(
          find.byType(AccountScreen),
          matchesGoldenFile('goldens/account_welcome_${w}_$b.png'),
        );
      });

      // Account with Security selected — light + dark.
      testWidgets('account security selected $w $b', (tester) async {
        await _pump(
          tester,
          location: '/account/security',
          child: () => const AccountShell(child: SecurityScreen()),
          width: width,
          brightness: brightness,
        );
        await expectLater(
          find.byType(AccountShell),
          matchesGoldenFile('goldens/account_security_${w}_$b.png'),
        );
      });
    }

    // Guest welcome — light only.
    testWidgets('account welcome guest $w light', (tester) async {
      await _pump(
        tester,
        location: '/account',
        child: () => const AccountScreen(),
        width: width,
        brightness: Brightness.light,
        user: null,
      );
      await expectLater(
        find.byType(AccountScreen),
        matchesGoldenFile('goldens/account_welcome_guest_${w}_light.png'),
      );
    });

    // Account with Profile selected — light only.
    testWidgets('account profile selected $w light', (tester) async {
      await _pump(
        tester,
        location: '/account/profile',
        child: () => const AccountShell(child: AccountProfileScreen()),
        width: width,
        brightness: Brightness.light,
      );
      await expectLater(
        find.byType(AccountShell),
        matchesGoldenFile('goldens/account_profile_${w}_light.png'),
      );
    });
  }
}
