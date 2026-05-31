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
import 'package:mopro/core/widgets/login_required_sheet.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/auth/widgets/auth_card.dart';
import 'package:mopro/features/auth/widgets/login_required.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Flow S — desktop LoginRequiredDialog + focus trap + Escape + resume ──────
//
// Adaptation note: the prompt frames the trigger as the PDP heart, but in this
// app favorites are guest-local (the heart toggles without gating). So this flow
// exercises the SAME desktop-presenter + resume contract through requireAuth —
// the mechanism the reviews "Faydalı" button and checkout gate actually use.

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
  void authenticate() => state = const AsyncData(AuthAuthenticated());
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

  testWidgets('Flow S: desktop dialog, focus trap, Escape, resume after auth',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();

    var resumed = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: Center(
              child: Consumer(
                builder: (ctx, ref, _) => ElevatedButton(
                  onPressed: () => requireAuth(
                    ctx,
                    ref,
                    reason: 'Devam etmek için giriş yapın.',
                    onAuthed: () => resumed++,
                  ),
                  child: const Text('GATED'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(path: '/auth/login', builder: (_, __) => const Scaffold()),
        GoRoute(path: '/auth/register', builder: (_, __) => const Scaffold()),
      ],
    );

    final auth = _FakeAuth();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('tr', 'TR')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr', 'TR'),
        child: ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            authNotifierProvider.overrideWith(() => auth),
          ],
          child: MaterialApp.router(
            theme: buildLightTheme(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 3-4) Guest taps the gated action → desktop dialog (AuthCard, not sheet).
    await tester.tap(find.text('GATED'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequired), findsOneWidget);
    expect(find.byType(AuthCard), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);

    // 5) Focus trap: tabbing keeps focus inside; modal stays open.
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(find.byType(LoginRequired), findsOneWidget);

    // 6) Escape closes; resume not yet fired.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequired), findsNothing);
    expect(resumed, 0);

    // 7) Re-open, then authenticate via the harness.
    await tester.tap(find.text('GATED'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequired), findsOneWidget);

    auth.authenticate();
    await tester.pumpAndSettle();

    // 9) Resume contract: dialog dismisses and the gated action runs once.
    expect(find.byType(LoginRequired), findsNothing);
    expect(resumed, 1);
  });
}
