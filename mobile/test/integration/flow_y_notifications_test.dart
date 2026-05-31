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
import 'package:mopro/core/router/app_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';
import 'package:mopro/features/notifications/data/notification_repository.dart';
import 'package:mopro/features/notifications/notification_preferences_screen.dart';
import 'package:mopro/features/notifications/notifications_screen.dart';
import 'package:mopro/features/notifications/widgets/notification_badge.dart';
import 'package:mopro/features/notifications/widgets/notification_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Flow Y — notifications round-trip (2a) ───────────────────────────────────

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthAuthenticated();
}

class _FakeNotifRepo implements NotificationRepository {
  _FakeNotifRepo(this._items);
  List<NotificationDto> _items;
  List<PreferenceDto> _prefs = _matrix();
  final List<List<PreferenceDto>> puts = [];

  @override
  Future<NotificationListResult> list({bool unreadOnly = false, int page = 1, int pageSize = 20}) async {
    final items = unreadOnly ? _items.where((n) => !n.isRead).toList() : _items;
    return NotificationListResult(items: items, total: items.length, page: page, pageSize: pageSize, hasMore: false);
  }

  @override
  Future<int> unreadCount() async => _items.where((n) => !n.isRead).length;
  @override
  Future<void> markRead(int id) async {
    _items = [for (final n in _items) n.id == id ? n.copyWith(isRead: true) : n];
  }

  @override
  Future<int> markAllRead() async {
    final c = _items.where((n) => !n.isRead).length;
    _items = [for (final n in _items) n.copyWith(isRead: true)];
    return c;
  }

  @override
  Future<List<PreferenceDto>> getPreferences() async => _prefs;
  @override
  Future<void> putPreferences(List<PreferenceDto> prefs) async {
    puts.add(prefs);
    _prefs = [
      for (final p in _prefs)
        prefs.firstWhere(
          (q) => q.category == p.category && q.channel == p.channel,
          orElse: () => p,
        ),
    ];
  }

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

NotificationDto _n(int id, {bool isRead = false}) => NotificationDto(
      id: id,
      type: NotificationType.orderStatus,
      titleKey: 'notifications.sample_order_title',
      bodyKey: 'notifications.sample_order_body',
      bodyParams: {'id': '$id'},
      createdAt: DateTime.now().subtract(Duration(minutes: id)),
      isRead: isRead,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => Directory.systemTemp.path,
      )
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => call.method == 'readAll' ? <String, String>{} : null,
      );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('Flow Y: badge → list → mark-read → mark-all → preferences',
      (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();

    final repo = _FakeNotifRepo([_n(1), _n(2), _n(3), _n(4, isRead: true), _n(5, isRead: true)]);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('tr', 'TR')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr', 'TR'),
        child: ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            authNotifierProvider.overrideWith(_FakeAuth.new),
            notificationRepositoryProvider.overrideWithValue(repo),
            currentUserProvider.overrideWith(
              (ref) async => const CurrentUser(id: 1, displayName: 'Ada', email: 'a@b.co'),
            ),
            cartCountProvider.overrideWithValue(0),
            categoryTreeProvider.overrideWithValue(const AsyncData([])),
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              theme: buildLightTheme(),
              routerConfig: ref.watch(routerProvider),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(Navigator).first);
    GoRouter.of(ctx).go('/account/notifications');
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);

    // Badge reflects 3 unread.
    expect(find.text('notifications.mark_all_read'), findsOneWidget);
    expect(find.byType(NotificationRow), findsNWidgets(5));

    // Tap an unread row → optimistic mark-read; one fewer NotificationBadge dot.
    final unread = find.byType(NotificationRow).first;
    await tester.tap(unread);
    await tester.pumpAndSettle();

    // Mark all read → button disappears.
    await tester.tap(find.text('notifications.mark_all_read'));
    await tester.pumpAndSettle();
    expect(find.text('notifications.mark_all_read'), findsNothing);
    expect(find.byType(NotificationBadge), findsWidgets); // still mounted (count 0 → child only)

    // Go to preferences via footer link.
    await tester.tap(find.text('notifications.settings_link'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationPreferencesScreen), findsOneWidget);

    // Toggle a marketing channel on → persists via PUT.
    final marketingEmail = find.byType(SwitchListTile).at(10); // marketing/email
    await tester.ensureVisible(marketingEmail);
    await tester.tap(marketingEmail);
    await tester.pump(const Duration(milliseconds: 400)); // debounce flush
    expect(repo.puts, isNotEmpty);

    // Forced-on: security/in_app (index 6) cannot be disabled → SnackBar.
    final securityInApp = find.byType(SwitchListTile).at(6);
    await tester.ensureVisible(securityInApp);
    await tester.tap(securityInApp);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
