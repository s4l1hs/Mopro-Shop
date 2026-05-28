import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/widgets/login_required_sheet.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/test_harness.dart';

/// In-memory AuthNotifier whose state can be flipped in tests.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._initial);
  final AuthState _initial;

  @override
  Future<AuthState> build() async => _initial;

  void setAuthed() => state = const AsyncData(AuthAuthenticated());
}

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const _Host()),
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
      ],
    );

class _Host extends StatelessWidget {
  const _Host();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showLoginRequiredSheet(
            context,
            reason: 'Test reason',
          ),
          child: const Text('OPEN_SHEET'),
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  AuthState initialAuth = const AuthUnauthenticated(),
  _FakeAuthNotifier? authNotifier,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final notifier = authNotifier ?? _FakeAuthNotifier(initialAuth);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authNotifierProvider.overrideWith(() => notifier),
      ],
      child: MaterialApp.router(
        theme: brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        routerConfig: _stubRouter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  group('LoginRequiredSheet behavior', () {
    testWidgets('opens with reason text and two CTAs', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('OPEN_SHEET'));
      await tester.pumpAndSettle();

      expect(find.text('Test reason'), findsOneWidget);
      expect(find.text('Giriş Yap'), findsOneWidget);
      expect(find.text('Üye Ol'), findsOneWidget);
      expect(find.text('Misafir olarak devam et'), findsOneWidget);
    });

    testWidgets('Giriş Yap navigates to /auth/login', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('OPEN_SHEET'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Giriş Yap'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_PAGE'), findsOneWidget);
    });

    testWidgets('Üye Ol navigates to /auth/register', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('OPEN_SHEET'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Üye Ol'));
      await tester.pumpAndSettle();

      expect(find.text('REGISTER_PAGE'), findsOneWidget);
    });

    testWidgets('Misafir dismiss closes the sheet', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('OPEN_SHEET'));
      await tester.pumpAndSettle();
      expect(find.text('Test reason'), findsOneWidget);

      await tester.tap(find.text('Misafir olarak devam et'));
      await tester.pumpAndSettle();
      expect(find.text('Test reason'), findsNothing);
    });

    testWidgets('auto-closes when auth flips to authenticated', (tester) async {
      final notifier = _FakeAuthNotifier(const AuthUnauthenticated());
      await _pump(tester, authNotifier: notifier);
      await tester.tap(find.text('OPEN_SHEET'));
      await tester.pumpAndSettle();
      expect(find.text('Test reason'), findsOneWidget);

      notifier.setAuthed();
      await tester.pumpAndSettle();

      expect(find.text('Test reason'), findsNothing);
    });
  });

  group('LoginRequiredSheet golden', () {
    testWidgets('light theme', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 560));
      await _pump(tester);
      await tester.tap(find.text('OPEN_SHEET'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(BottomSheet),
        matchesGoldenFile('goldens/login_required_sheet_light.png'),
      );
    });

    testWidgets('dark theme', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 560));
      await _pump(tester, brightness: Brightness.dark);
      await tester.tap(find.text('OPEN_SHEET'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(BottomSheet),
        matchesGoldenFile('goldens/login_required_sheet_dark.png'),
      );
    });
  });
}
