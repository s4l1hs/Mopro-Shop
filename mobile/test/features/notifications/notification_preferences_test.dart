import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/notifications/application/notification_preferences_provider.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';
import 'package:mopro/features/notifications/data/notification_repository.dart';
import 'package:mopro/features/notifications/notification_preferences_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo implements NotificationRepository {
  _FakeRepo(this.stored);
  List<PreferenceDto> stored;
  final List<List<PreferenceDto>> puts = [];

  @override
  Future<List<PreferenceDto>> getPreferences() async => stored;
  @override
  Future<void> putPreferences(List<PreferenceDto> prefs) async => puts.add(prefs);
  @override
  Future<NotificationListResult> list({bool unreadOnly = false, int page = 1, int pageSize = 20}) async =>
      const NotificationListResult(items: [], total: 0, page: 1, pageSize: 20, hasMore: false);
  @override
  Future<int> unreadCount() async => 0;
  @override
  Future<void> markRead(int id) async {}
  @override
  Future<int> markAllRead() async => 0;
  @override
  Future<void> registerPushToken({required String token, required String platform}) async {}
  @override
  Future<void> deletePushToken(String token) async {}
}

List<PreferenceDto> _matrix() => [
      for (final c in ['order_status', 'return_update', 'security', 'marketing', 'general'])
        for (final ch in ['in_app', 'email', 'push'])
          PreferenceDto(category: c, channel: ch, enabled: c != 'marketing'),
    ];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  group('isForcedOn', () {
    test('security/orders/returns in_app are forced on', () {
      expect(isForcedOn('security', 'in_app'), isTrue);
      expect(isForcedOn('order_status', 'in_app'), isTrue);
      expect(isForcedOn('return_update', 'in_app'), isTrue);
      expect(isForcedOn('marketing', 'in_app'), isFalse);
      expect(isForcedOn('security', 'email'), isFalse);
    });
  });

  test('toggle: forced-on disable is rejected; marketing toggle persists', () async {
    final repo = _FakeRepo(_matrix());
    final c = ProviderContainer(
      overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    final n = c.read(notificationPreferencesProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20)); // load

    expect(n.toggle(category: 'security', channel: 'in_app', enabled: false), isFalse);
    expect(c.read(notificationPreferencesProvider).isEnabled('security', 'in_app'), isTrue);

    expect(n.toggle(category: 'marketing', channel: 'email', enabled: true), isTrue);
    await n.flushNow();
    expect(repo.puts.single.single.category, 'marketing');
    expect(repo.puts.single.single.enabled, isTrue);
  });

  testWidgets('preferences screen renders the full grid + forced-on SnackBar',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 3000); // tall: all 15 tiles attach
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _FakeRepo(_matrix());
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('tr', 'TR')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr', 'TR'),
        child: ProviderScope(
          overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: NotificationPreferencesScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 5 categories × 3 channels.
    expect(find.byType(SwitchListTile), findsNWidgets(15));

    // security/in_app is the 7th switch (orderStatus 3 + returnUpdate 3 + 1).
    await tester.tap(find.byType(SwitchListTile).at(6));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('forced_on_warning'), findsOneWidget);
  });
}
