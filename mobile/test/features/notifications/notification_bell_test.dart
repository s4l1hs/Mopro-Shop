import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/notifications/application/notifications_provider.dart';
import 'package:mopro/features/notifications/widgets/notification_bell.dart';

import '../../_support/stub_unread_count.dart';
import '../../_support/test_harness.dart';

/// Unread-count stub fixed at [_count] (no poll timer leak).
class _FixedUnread extends UnreadCountNotifier {
  _FixedUnread(this._count);
  final int _count;
  @override
  int build() => _count;
}

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: NotificationBell(
              onTap: () => context.go('/account/notifications'),
            ),
          ),
        ),
        GoRoute(
          path: '/account/notifications',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('INBOX'))),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, {int count = 0}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unreadNotificationCountProvider.overrideWith(() => _FixedUnread(count)),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('renders the bell glyph', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
  });

  testWidgets('no badge for a guest / zero unread', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('notification-badge')), findsNothing);
  });

  testWidgets('shows the unread badge when count > 0', (tester) async {
    await _pump(tester, count: 5);
    expect(find.byKey(const ValueKey('notification-badge')), findsOneWidget);
  });

  testWidgets('tap routes to the inbox', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('INBOX'), findsOneWidget);
  });

  testWidgets('shared stub override hides the badge', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [stubUnreadCountOverride],
        child: MaterialApp(
          home: Scaffold(body: NotificationBell(onTap: () {})),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-badge')), findsNothing);
  });
}
