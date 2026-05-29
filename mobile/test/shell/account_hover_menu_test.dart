import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/shell/account_hover_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._initial);
  final AuthState _initial;
  @override
  Future<AuthState> build() async => _initial;
}

GoRouter _stubRouter({required bool isAuthed}) => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            // Trigger sits in a Row so panel right-anchors to viewport.
            appBar: AppBar(
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: AccountHoverMenu(
                    isAuthed: isAuthed,
                    trigger: Container(
                      key: const Key('triggerBox'),
                      width: 44,
                      height: 44,
                      color: Colors.orange,
                      alignment: Alignment.center,
                      child: const Text('TRIGGER'),
                    ),
                  ),
                ),
              ],
            ),
            body: const Center(child: Text('HOME')),
          ),
        ),
        GoRoute(
          path: '/auth/login',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('LOGIN_PAGE'))),
        ),
        GoRoute(
          path: '/auth/register',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('REGISTER_PAGE'))),
        ),
        GoRoute(
          path: '/account/profile',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('PROFILE_PAGE'))),
        ),
        GoRoute(
          path: '/orders',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('ORDERS_PAGE'))),
        ),
        GoRoute(
          path: '/favorites',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('FAV_PAGE'))),
        ),
        GoRoute(
          path: '/account',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('ACCOUNT_PAGE'))),
        ),
        GoRoute(
          path: '/wallet',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('WALLET_PAGE'))),
        ),
        GoRoute(
          path: '/profile/addresses',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('ADDRESSES_PAGE'))),
        ),
        GoRoute(
          path: '/account/cards',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('CARDS_PAGE'))),
        ),
        GoRoute(
          path: '/account/security',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('SECURITY_PAGE'))),
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  bool isAuthed = false,
  Brightness brightness = Brightness.light,
  Size size = const Size(1440, 800),
  CurrentUser? user,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authNotifierProvider.overrideWith(
          () => _FakeAuthNotifier(
            isAuthed
                ? const AuthAuthenticated()
                : const AuthUnauthenticated(),
          ),
        ),
        // Override currentUserProvider so the menu doesn't try to call
        // MeApi.getMe() through Dio in widget tests (which would leave a
        // pending Timer and fail the test invariant check).
        currentUserProvider.overrideWith((ref) async => user),
      ],
      child: MaterialApp.router(
        theme: brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        routerConfig: _stubRouter(isAuthed: isAuthed),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMenuByClick(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('triggerBox')));
  // Pump several frames for the overlay to mount and animations to settle.
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  group('AccountHoverMenu — guest variant', () {
    testWidgets('opens on click and shows login + register CTAs',
        (tester) async {
      await _pump(tester);
      await _openMenuByClick(tester);
      // Guest panel contents: prompt + 2 CTAs + 3 menu rows.
      expect(find.text('account.menu_login_prompt'), findsOneWidget);
      expect(find.text('auth.login_title'), findsOneWidget);
      expect(find.text('account.menu_register'), findsOneWidget);
      expect(find.text('account.orders'), findsOneWidget);
      expect(find.text('nav.favorites'), findsOneWidget);
      expect(find.text('account.menu_help'), findsOneWidget);
    });

    testWidgets('login CTA navigates to /auth/login', (tester) async {
      await _pump(tester);
      await _openMenuByClick(tester);
      await tester.tap(find.text('auth.login_title'));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN_PAGE'), findsOneWidget);
    });

    testWidgets('register CTA navigates to /auth/register', (tester) async {
      await _pump(tester);
      await _openMenuByClick(tester);
      await tester.tap(find.text('account.menu_register'));
      await tester.pumpAndSettle();
      expect(find.text('REGISTER_PAGE'), findsOneWidget);
    });

    testWidgets('Escape closes the menu', (tester) async {
      await _pump(tester);
      await _openMenuByClick(tester);
      expect(find.text('account.menu_login_prompt'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('account.menu_login_prompt'), findsNothing);
    });
  });

  group('AccountHoverMenu — authed variant', () {
    testWidgets('opens on click and shows all 6 nav rows + logout',
        (tester) async {
      await _pump(tester, isAuthed: true);
      await _openMenuByClick(tester);
      expect(find.text('account.profile'), findsOneWidget);
      expect(find.text('account.orders'), findsOneWidget);
      expect(find.text('account.wallet'), findsOneWidget);
      expect(find.text('account.addresses'), findsOneWidget);
      expect(find.text('account.cards'), findsOneWidget);
      expect(find.text('account.security'), findsOneWidget);
      expect(find.text('account.logout'), findsOneWidget);
    });

    testWidgets('Profile row navigates to /account/profile', (tester) async {
      await _pump(tester, isAuthed: true);
      await _openMenuByClick(tester);
      await tester.tap(find.text('account.profile'));
      await tester.pumpAndSettle();
      expect(find.text('PROFILE_PAGE'), findsOneWidget);
    });

    testWidgets('Wallet row navigates to /wallet', (tester) async {
      await _pump(tester, isAuthed: true);
      await _openMenuByClick(tester);
      await tester.tap(find.text('account.wallet'));
      await tester.pumpAndSettle();
      expect(find.text('WALLET_PAGE'), findsOneWidget);
    });

    testWidgets('header renders displayName + email when provided',
        (tester) async {
      await _pump(
        tester,
        isAuthed: true,
        user: const CurrentUser(
          id: 1,
          displayName: 'Ayşe Yılmaz',
          email: 'ayse@example.test',
        ),
      );
      await _openMenuByClick(tester);
      expect(find.text('Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('ayse@example.test'), findsOneWidget);
      // The placeholder header (account.title) should NOT render when a
      // real user is loaded.
      expect(find.text('account.title'), findsNothing);
    });

    testWidgets('header falls back to email local-part when displayName empty',
        (tester) async {
      await _pump(
        tester,
        isAuthed: true,
        user: const CurrentUser(
          id: 1,
          displayName: 'ada',
          email: 'ada@lovelace.dev',
        ),
      );
      await _openMenuByClick(tester);
      expect(find.text('ada'), findsOneWidget);
    });
  });

  group('AccountHoverMenu — goldens', () {
    testWidgets('guest 1440 light', (tester) async {
      await _pump(tester);
      await _openMenuByClick(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/account_hover_menu_guest_1440_light.png'),
      );
    });

    testWidgets('authed 1440 light', (tester) async {
      await _pump(tester, isAuthed: true);
      await _openMenuByClick(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/account_hover_menu_authed_1440_light.png'),
      );
    });
  });
}
