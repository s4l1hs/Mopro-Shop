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
import 'package:mopro/features/help/contact_form_screen.dart';
import 'package:mopro/features/help/data/help_dto.dart';
import 'package:mopro/features/help/data/help_repository.dart';
import 'package:mopro/features/help/help_article_screen.dart';
import 'package:mopro/features/help/help_index_screen.dart';
import 'package:mopro/features/help/help_search_screen.dart';
import 'package:mopro/features/help/widgets/help_category_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _GuestAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
}

class _FakeHelpRepo implements HelpRepository {
  @override
  Future<List<HelpCategoryDto>> categories() async => const [
        HelpCategoryDto(slug: 'account', title: 'Hesabım', articleCount: 6, iconName: 'person_outline'),
        HelpCategoryDto(slug: 'orders', title: 'Siparişlerim', articleCount: 6, iconName: 'shopping_bag_outlined'),
        HelpCategoryDto(slug: 'returns', title: 'İadeler', articleCount: 6, iconName: 'assignment_return_outlined'),
        HelpCategoryDto(slug: 'payment', title: 'Ödeme', articleCount: 6, iconName: 'shield_outlined'),
      ];
  @override
  Future<List<HelpArticleDto>> articles(String s) async =>
      const [HelpArticleDto(slug: 'start-return', title: 'İade başlat')];
  @override
  Future<HelpArticleDto> article(String slug) async => const HelpArticleDto(
        slug: 'start-return', title: 'İade nasıl başlatılır', body: '## Adımlar\n\nSipariş detayından başlat.',
        categorySlug: 'returns',
      );
  @override
  Future<List<HelpSearchResultDto>> search(String q) async => const [
        HelpSearchResultDto(slug: 'start-return', title: '**İade** başlat', snippet: '...**iade**...', categorySlug: 'returns'),
      ];
  @override
  Future<TicketDto> createTicket(CreateTicketRequest req) async => const TicketDto(id: 777, status: 'open');
}

Future<void> _boot(WidgetTester tester, {required Size size, required bool authed}) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          helpRepositoryProvider.overrideWithValue(_FakeHelpRepo()),
          authNotifierProvider.overrideWith(_GuestAuth.new),
          currentUserProvider.overrideWith((ref) async => null),
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
}

void _go(WidgetTester tester, String path) {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(path);
}

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

  testWidgets('Flow Z: guest help → search → article → contact → submit',
      (tester) async {
    await _boot(tester, size: const Size(390, 900), authed: false);

    _go(tester, '/help');
    await tester.pumpAndSettle();
    expect(find.byType(HelpIndexScreen), findsOneWidget);
    expect(find.byType(HelpCategoryCard), findsNWidgets(4));

    // Search "iade" → results.
    await tester.enterText(find.byType(TextField).first, 'iade');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byType(HelpSearchScreen), findsOneWidget);

    // Tap result → article.
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(HelpArticleScreen), findsOneWidget);

    // Bize Ulaş → contact, prefilled with article context.
    await tester.tap(find.textContaining('help.contact_cta'));
    await tester.pumpAndSettle();
    expect(find.byType(ContactFormScreen), findsOneWidget);
    expect(currentLocation(tester), contains('article=start-return'));

    // Fill + submit → success state.
    await tester.enterText(find.byType(TextField).first, 'guest@x.co');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('help.ticket_cat_other').last);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'Konu başlığı');
    await tester.enterText(fields.at(2), 'Mesaj gövdesi yeterince uzun.');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('contact_ticket_no'), findsOneWidget);
  });

  testWidgets('Flow Z: desktop index renders the category grid', (tester) async {
    await _boot(tester, size: const Size(1440, 1000), authed: false);
    _go(tester, '/help');
    await tester.pumpAndSettle();
    expect(find.byType(HelpIndexScreen), findsOneWidget);
    expect(find.byType(HelpCategoryCard), findsNWidgets(4));
  });
}

String currentLocation(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Navigator).first))
        .routeInformationProvider
        .value
        .uri
        .toString();
