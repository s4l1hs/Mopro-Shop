import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/notifications/application/notifications_provider.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';
import 'package:mopro/features/notifications/widgets/notification_badge.dart';
import 'package:mopro/features/notifications/widgets/notification_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCount extends UnreadCountNotifier {
  _FakeCount(this._n);
  final int _n;
  @override
  int build() => _n; // no timer / no polling under test
}

Widget _wrap(Widget child, {int count = 0}) => EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          unreadNotificationCountProvider.overrideWith(() => _FakeCount(count)),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

NotificationDto _notif({bool isRead = false}) => NotificationDto(
      id: 1,
      type: NotificationType.orderStatus,
      titleKey: 'notifications.sample_order_title',
      bodyKey: 'notifications.sample_order_body',
      bodyParams: const {'id': '42'},
      createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      isRead: isRead,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  const badge = Key('notification-badge');
  group('NotificationBadge', () {
    testWidgets('count 0 → just the child, no badge', (tester) async {
      await tester.pumpWidget(_wrap(const NotificationBadge(child: Icon(Icons.person))));
      await tester.pump();
      expect(find.byKey(badge), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('count 3 → small dot', (tester) async {
      await tester.pumpWidget(_wrap(const NotificationBadge(child: Icon(Icons.person)), count: 3));
      await tester.pump();
      expect(find.byKey(badge), findsOneWidget);
      expect(find.text('9+'), findsNothing);
    });

    testWidgets('count 12 → 9+ pill', (tester) async {
      await tester.pumpWidget(_wrap(const NotificationBadge(child: Icon(Icons.person)), count: 12));
      await tester.pump();
      expect(find.byKey(badge), findsOneWidget);
      expect(find.text('9+'), findsOneWidget);
    });
  });

  group('NotificationRow', () {
    testWidgets('unread shows orange left bar + type icon; tap fires', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(NotificationRow(item: _notif(), onTap: () => tapped = true)),
      );
      await tester.pump();
      expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
      await tester.tap(find.byType(NotificationRow));
      expect(tapped, isTrue);
    });

    testWidgets('read variant renders without crashing', (tester) async {
      await tester.pumpWidget(
        _wrap(NotificationRow(item: _notif(isRead: true), onTap: () {})),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
