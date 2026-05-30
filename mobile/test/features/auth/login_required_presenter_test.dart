import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/widgets/login_required_sheet.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/auth/widgets/auth_card.dart';
import 'package:mopro/features/auth/widgets/login_required.dart';

import '../../_support/test_harness.dart';

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
  void signIn() => state = const AsyncData(AuthAuthenticated());
}

Future<bool> _openAndReturnResumed(
  WidgetTester tester, {
  required Size size,
  bool authenticateWhileOpen = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  var resumed = false;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authNotifierProvider.overrideWith(_FakeAuth.new)],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: Consumer(
          builder: (ctx, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => requireAuth(
                  ctx,
                  ref,
                  reason: 'Test reason',
                  onAuthed: () => resumed = true,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();

  if (authenticateWhileOpen) {
    final container = ProviderScope.containerOf(tester.element(find.text('go')));
    (container.read(authNotifierProvider.notifier) as _FakeAuth).signIn();
    await tester.pumpAndSettle();
  }
  return resumed;
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('mobile (<600) opens a bottom sheet, not a dialog', (tester) async {
    await _openAndReturnResumed(tester, size: const Size(375, 800));
    expect(find.byType(LoginRequired), findsOneWidget);
    expect(find.byType(AuthCard), findsNothing);
  });

  testWidgets('desktop (>=600) opens an AuthCard dialog', (tester) async {
    await _openAndReturnResumed(tester, size: const Size(1440, 900));
    expect(find.byType(AuthCard), findsOneWidget);
    expect(find.byType(LoginRequired), findsOneWidget);
  });

  testWidgets('both presenters fire onResume after auth (sheet)', (tester) async {
    final resumed = await _openAndReturnResumed(
      tester,
      size: const Size(375, 800),
      authenticateWhileOpen: true,
    );
    expect(resumed, isTrue);
    expect(find.byType(LoginRequired), findsNothing); // dismissed
  });

  testWidgets('both presenters fire onResume after auth (dialog)',
      (tester) async {
    final resumed = await _openAndReturnResumed(
      tester,
      size: const Size(1440, 900),
      authenticateWhileOpen: true,
    );
    expect(resumed, isTrue);
    expect(find.byType(AuthCard), findsNothing); // dismissed
  });

  testWidgets('dialog closes on Escape', (tester) async {
    await _openAndReturnResumed(tester, size: const Size(1440, 900));
    expect(find.byType(AuthCard), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AuthCard), findsNothing);
  });

  testWidgets('dialog closes on barrier tap', (tester) async {
    await _openAndReturnResumed(tester, size: const Size(1440, 900));
    expect(find.byType(AuthCard), findsOneWidget);
    await tester.tapAt(const Offset(20, 20)); // outside the card
    await tester.pumpAndSettle();
    expect(find.byType(AuthCard), findsNothing);
  });
}
