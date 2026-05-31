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
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/account/widgets/account_left_rail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._initial);
  final AuthState _initial;
  int logoutCalls = 0;
  @override
  Future<AuthState> build() async => _initial;
  @override
  Future<void> setLoggedOut() async => logoutCalls++;
}

Future<_FakeAuth> _pumpRail(
  WidgetTester tester, {
  required String location,
  CurrentUser? user,
  AuthState auth = const AuthAuthenticated(),
}) async {
  tester.view.physicalSize = const Size(320, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final fakeAuth = _FakeAuth(auth);

  final router = GoRouter(
    initialLocation: location,
    routes: [
      for (final p in const [
        '/account/profile',
        '/account/security',
        '/orders',
        '/wallet',
        '/help',
        '/',
      ])
        GoRoute(
          path: p,
          builder: (_, __) => const Scaffold(body: AccountLeftRail()),
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
          currentUserProvider.overrideWith((ref) async => user),
          authNotifierProvider.overrideWith(() => fakeAuth),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          routerConfig: router,
        ),
      ),
    ),
  );
  // Resolve currentUserProvider (lazy FutureProvider) before asserting.
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AccountLeftRail)),
  );
  await container.read(currentUserProvider.future);
  await tester.pumpAndSettle();
  return fakeAuth;
}

FontWeight? _labelWeight(WidgetTester tester, String key) {
  final text = tester.widget<Text>(find.text(key));
  return text.style?.fontWeight;
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

  group('CurrentUser.initials', () {
    test('two words → first letters of first + second', () {
      expect(
        const CurrentUser(id: 1, displayName: 'Ada Lovelace').initials,
        'AL',
      );
    });
    test('one word → first letter', () {
      expect(const CurrentUser(id: 1, displayName: 'Ada').initials, 'A');
    });
    test('email local-part style (one token) → first letter', () {
      expect(const CurrentUser(id: 1, displayName: 'ada').initials, 'A');
    });
    test('empty → M fallback', () {
      expect(const CurrentUser(id: 1, displayName: '').initials, 'M');
    });
  });

  group('AccountLeftRail variants', () {
    testWidgets('authed variant shows user + logout row', (tester) async {
      await _pumpRail(
        tester,
        location: '/account/security',
        user: const CurrentUser(
          id: 1,
          displayName: 'Ada Lovelace',
          email: 'ada@example.com',
        ),
      );
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
      expect(find.text('account.logout'), findsOneWidget);
      expect(find.text('account.orders'), findsOneWidget);
    });

    testWidgets('guest variant shows login/register, no logout/orders',
        (tester) async {
      await _pumpRail(
        tester,
        location: '/help',
        auth: const AuthUnauthenticated(),
      );
      expect(find.text('account.menu_login_prompt'), findsOneWidget);
      expect(find.text('auth.login'), findsOneWidget);
      expect(find.text('account.menu_register'), findsOneWidget);
      expect(find.text('account.logout'), findsNothing);
      expect(find.text('account.orders'), findsNothing);
    });
  });

  group('AccountLeftRail active highlight', () {
    testWidgets('security highlighted on /account/security', (tester) async {
      await _pumpRail(
        tester,
        location: '/account/security',
        user: const CurrentUser(id: 1, displayName: 'Ada'),
      );
      expect(_labelWeight(tester, 'account.security'), FontWeight.w700);
      expect(_labelWeight(tester, 'account.orders'), FontWeight.w400);
    });

    testWidgets('orders highlighted on /orders', (tester) async {
      await _pumpRail(
        tester,
        location: '/orders',
        user: const CurrentUser(id: 1, displayName: 'Ada'),
      );
      expect(_labelWeight(tester, 'account.orders'), FontWeight.w700);
      expect(_labelWeight(tester, 'account.security'), FontWeight.w400);
    });
  });

  group('AccountLeftRail interactions', () {
    testWidgets('Tema row expands the theme picker inline', (tester) async {
      await _pumpRail(
        tester,
        location: '/account/security',
        user: const CurrentUser(id: 1, displayName: 'Ada'),
      );
      expect(find.text('account.theme_light'), findsNothing);
      await tester.tap(find.text('account.theme'));
      await tester.pumpAndSettle();
      expect(find.text('account.theme_light'), findsOneWidget);
      expect(find.text('account.theme_dark'), findsOneWidget);
    });

    testWidgets('Çıkış Yap calls logout exactly once', (tester) async {
      final auth = await _pumpRail(
        tester,
        location: '/account/security',
        user: const CurrentUser(id: 1, displayName: 'Ada'),
      );
      await tester.tap(find.text('account.logout'));
      await tester.pumpAndSettle();
      expect(auth.logoutCalls, 1);
    });
  });
}
