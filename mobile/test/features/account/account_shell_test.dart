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
import 'package:mopro/features/account/cards_screen.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/account/widgets/account_left_rail.dart';
import 'package:mopro/features/account/widgets/account_rail_item.dart';
import 'package:mopro/features/account/widgets/account_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../_support/stub_unread_count.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._initial);
  final AuthState _initial;
  @override
  Future<AuthState> build() async => _initial;
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  AuthState auth = const AuthAuthenticated(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/account/security',
    routes: [
      ShellRoute(
        builder: (_, __, child) => AccountShell(child: child),
        routes: [
          GoRoute(
            path: '/account/security',
            builder: (_, __) => const CardsScreen(), // any chrome-gated screen
          ),
        ],
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
          sharedPreferencesProvider.overrideWithValue(prefs),
          stubUnreadCountOverride,
          currentUserProvider.overrideWith((ref) async => null),
          authNotifierProvider.overrideWith(() => _FakeAuth(auth)),
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
  group('accountRailItemFor', () {
    test('maps each path to its item and sub-routes inherit', () {
      expect(accountRailItemFor('/account'), AccountRailItem.none);
      expect(accountRailItemFor('/account/profile'), AccountRailItem.profile);
      expect(accountRailItemFor('/account/security'), AccountRailItem.security);
      expect(accountRailItemFor('/account/cards'), AccountRailItem.cards);
      expect(
        accountRailItemFor('/account/notifications'),
        AccountRailItem.notifications,
      );
      expect(accountRailItemFor('/orders'), AccountRailItem.orders);
      expect(accountRailItemFor('/orders/42'), AccountRailItem.orders);
      expect(accountRailItemFor('/wallet'), AccountRailItem.wallet);
      expect(accountRailItemFor('/wallet/plans/7'), AccountRailItem.wallet);
      expect(
        accountRailItemFor('/profile/addresses'),
        AccountRailItem.addresses,
      );
      expect(
        accountRailItemFor('/profile/addresses/new'),
        AccountRailItem.addresses,
      );
      expect(accountRailItemFor('/help'), AccountRailItem.help);
      expect(accountRailItemFor('/'), AccountRailItem.none);
    });
  });

  group('AccountChromeScope', () {
    testWidgets('suppresses the screen app bar only under the scope',
        (tester) async {
      // Standalone: app bar present.
      await tester.pumpWidget(
        const MaterialApp(home: CardsScreen()),
      );
      expect(find.byType(AppBar), findsOneWidget);

      // Under the scope: app bar suppressed.
      await tester.pumpWidget(
        const MaterialApp(
          home: AccountChromeScope(
            suppressAppBar: true,
            child: CardsScreen(),
          ),
        ),
      );
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('AccountShell composition', () {
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

    testWidgets('desktop renders the rail + child with chrome suppressed',
        (tester) async {
      await _pumpShell(tester, size: const Size(1440, 900));
      expect(find.byType(AccountLeftRail), findsOneWidget);
      expect(find.byType(CardsScreen), findsOneWidget);
      // The child's own app bar is suppressed inside the shell.
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('mobile is a pass-through: no rail, child keeps its app bar',
        (tester) async {
      await _pumpShell(tester, size: const Size(390, 800));
      expect(find.byType(AccountLeftRail), findsNothing);
      expect(find.byType(CardsScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
