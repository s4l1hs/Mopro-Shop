import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/notifications/application/notifications_provider.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';
import 'package:mopro/features/notifications/data/notification_repository.dart';
import 'package:mopro/features/notifications/notifications_screen.dart';
import 'package:mopro/features/notifications/widgets/notification_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo implements NotificationRepository {
  _FakeRepo(this._items, {this.markReadThrows = false});
  final List<NotificationDto> _items;
  final bool markReadThrows;
  int markReadCalls = 0;
  int markAllCalls = 0;

  @override
  Future<NotificationListResult> list({bool unreadOnly = false, int page = 1, int pageSize = 20}) async {
    final items = unreadOnly ? _items.where((n) => !n.isRead).toList() : _items;
    return NotificationListResult(
      items: items, total: items.length, page: page, pageSize: pageSize, hasMore: false,
    );
  }

  @override
  Future<int> unreadCount() async => _items.where((n) => !n.isRead).length;
  @override
  Future<void> markRead(int id) async {
    markReadCalls++;
    if (markReadThrows) throw Exception('boom');
  }

  @override
  Future<int> markAllRead() async {
    markAllCalls++;
    return _items.where((n) => !n.isRead).length;
  }

  @override
  Future<List<PreferenceDto>> getPreferences() async => [];
  @override
  Future<void> putPreferences(List<PreferenceDto> prefs) async {}
  @override
  Future<void> registerPushToken({required String token, required String platform}) async {}
  @override
  Future<void> deletePushToken(String token) async {}
}

NotificationDto _n(int id, {bool isRead = false}) => NotificationDto(
      id: id,
      type: NotificationType.orderStatus,
      titleKey: 'notifications.sample_order_title',
      bodyKey: 'notifications.sample_order_body',
      bodyParams: {'id': '$id'},
      createdAt: DateTime.now().subtract(Duration(minutes: id)),
      isRead: isRead,
    );

class _FakeCount extends UnreadCountNotifier {
  @override
  int build() => 0;
}

Future<void> _pump(WidgetTester tester, _FakeRepo repo) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repo),
          unreadNotificationCountProvider.overrideWith(_FakeCount.new),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('populated list renders rows + mark-all when unread', (tester) async {
    await _pump(tester, _FakeRepo([_n(1), _n(2, isRead: true), _n(3)]));
    expect(find.byType(NotificationRow), findsNWidgets(3));
    expect(find.text('notifications.mark_all_read'), findsOneWidget);
  });

  testWidgets('mark-all hidden when nothing unread', (tester) async {
    await _pump(tester, _FakeRepo([_n(1, isRead: true)]));
    expect(find.text('notifications.mark_all_read'), findsNothing);
  });

  testWidgets('empty state renders', (tester) async {
    await _pump(tester, _FakeRepo([]));
    expect(find.text('notifications.empty'), findsOneWidget);
  });

  testWidgets('mark-read optimistic, rolls back on server error', (tester) async {
    final repo = _FakeRepo([_n(1)], markReadThrows: true);
    await _pump(tester, repo);
    // Tap the unread row → optimistic read, then rollback after the throw.
    await tester.tap(find.byType(NotificationRow).first);
    await tester.pump(); // optimistic
    await tester.pump(const Duration(milliseconds: 50)); // await throw + rollback
    expect(repo.markReadCalls, 1);
    // After rollback the item is unread again → mark-all button still present.
    expect(find.text('notifications.mark_all_read'), findsOneWidget);
  });
}
