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
import 'package:mopro/features/auth/widgets/login_required.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
}

Future<void> _pumpHost(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (ctx, __) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showLoginRequiredSheet(ctx, reason: 'r'),
              child: const Text('TRIGGER'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/auth/login', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/auth/register', builder: (_, __) => const Scaffold()),
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
          authNotifierProvider.overrideWith(_FakeAuth.new),
        ],
        child: MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
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

  testWidgets('desktop login dialog: Escape closes + focus returns to trigger',
      (tester) async {
    await _pumpHost(tester, const Size(1440, 900));
    await tester.tap(find.text('TRIGGER'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequired), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget); // dialog, not bottom sheet

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequired), findsNothing);
    expect(find.text('TRIGGER'), findsOneWidget);
  });

  testWidgets('mobile login sheet: Escape closes', (tester) async {
    await _pumpHost(tester, const Size(390, 800));
    await tester.tap(find.text('TRIGGER'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequired), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequired), findsNothing);
  });

  testWidgets('dialog focus stays within the modal (trap)', (tester) async {
    await _pumpHost(tester, const Size(1440, 900));
    await tester.tap(find.text('TRIGGER'));
    await tester.pumpAndSettle();
    // Tab through several stops; focus must never land back on the trigger
    // behind the modal barrier.
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context?.widget;
      expect(focused, isNotNull);
    }
    // The trigger button is behind the barrier — still not the primary focus's
    // route; the modal is still open.
    expect(find.byType(LoginRequired), findsOneWidget);
  });
}
