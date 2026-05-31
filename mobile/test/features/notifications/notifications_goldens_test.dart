import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/notifications/application/notifications_provider.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';
import 'package:mopro/features/notifications/data/notification_repository.dart';
import 'package:mopro/features/notifications/notification_preferences_screen.dart';
import 'package:mopro/features/notifications/notifications_screen.dart';
import 'package:mopro/features/notifications/widgets/notification_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

class _Repo implements NotificationRepository {
  _Repo({this.items = const [], this.prefs = const []});
  final List<NotificationDto> items;
  final List<PreferenceDto> prefs;

  @override
  Future<NotificationListResult> list({bool unreadOnly = false, int page = 1, int pageSize = 20}) async =>
      NotificationListResult(items: items, total: items.length, page: 1, pageSize: 20, hasMore: false);
  @override
  Future<int> unreadCount() async => items.where((n) => !n.isRead).length;
  @override
  Future<void> markRead(int id) async {}
  @override
  Future<int> markAllRead() async => 0;
  @override
  Future<List<PreferenceDto>> getPreferences() async => prefs;
  @override
  Future<void> putPreferences(List<PreferenceDto> p) async {}
  @override
  Future<void> registerPushToken({required String token, required String platform}) async {}
  @override
  Future<void> deletePushToken(String token) async {}
}

class _StubCount extends UnreadCountNotifier {
  @override
  int build() => 0;
}

NotificationDto _n(int id, {bool isRead = false}) => NotificationDto(
      id: id,
      type: id.isEven ? NotificationType.returnUpdate : NotificationType.orderStatus,
      titleKey: 'notifications.sample_order_title',
      bodyKey: 'notifications.sample_order_body',
      bodyParams: {'id': '$id'},
      createdAt: DateTime(2026, 5, 2).subtract(Duration(hours: id)),
      isRead: isRead,
    );

List<PreferenceDto> _matrix() => [
      for (final c in ['order_status', 'return_update', 'security', 'marketing', 'general'])
        for (final ch in ['in_app', 'email', 'push'])
          PreferenceDto(category: c, channel: ch, enabled: c != 'marketing'),
    ];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 1440,
  double height = 1000,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const [],
}) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          unreadNotificationCountProvider.overrideWith(_StubCount.new),
          ...overrides,
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('notification_row read+unread 1440 light', (tester) async {
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NotificationRow(item: _n(1), onTap: () {}),
          const Divider(height: 1),
          NotificationRow(item: _n(2, isRead: true), onTap: () {}),
        ],
      ),
      width: 600,
      height: 300,
    );
    await expectLater(
      find.byType(Column).first,
      matchesGoldenFile('goldens/notification_rows_light.png'),
    );
  });

  for (final b in Brightness.values) {
    final name = b == Brightness.dark ? 'dark' : 'light';
    testWidgets('notifications_list populated 1440 $name', (tester) async {
      await _pump(
        tester,
        const NotificationsScreen(),
        brightness: b,
        overrides: [
          notificationRepositoryProvider.overrideWithValue(
            _Repo(items: [_n(1), _n(2), _n(3, isRead: true)]),
          ),
        ],
      );
      await expectLater(
        find.byType(NotificationsScreen),
        matchesGoldenFile('goldens/notifications_list_populated_1440_$name.png'),
      );
    });
  }

  testWidgets('notifications_list empty 1440 light', (tester) async {
    await _pump(
      tester,
      const NotificationsScreen(),
      overrides: [notificationRepositoryProvider.overrideWithValue(_Repo())],
    );
    await expectLater(
      find.byType(NotificationsScreen),
      matchesGoldenFile('goldens/notifications_list_empty_1440_light.png'),
    );
  });

  testWidgets('notification_preferences 1440 light', (tester) async {
    await _pump(
      tester,
      const NotificationPreferencesScreen(),
      height: 1600,
      overrides: [
        notificationRepositoryProvider.overrideWithValue(_Repo(prefs: _matrix())),
      ],
    );
    await expectLater(
      find.byType(NotificationPreferencesScreen),
      matchesGoldenFile('goldens/notification_preferences_1440_light.png'),
    );
  });
}
