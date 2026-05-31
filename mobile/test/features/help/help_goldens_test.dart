import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/help/contact_form_screen.dart';
import 'package:mopro/features/help/data/help_dto.dart';
import 'package:mopro/features/help/data/help_repository.dart';
import 'package:mopro/features/help/help_article_screen.dart';
import 'package:mopro/features/help/help_index_screen.dart';
import 'package:mopro/features/help/help_search_screen.dart';
import 'package:mopro/features/help/widgets/help_category_card.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'help_test_support.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 1440,
  double height = 1200,
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
          helpRepositoryProvider.overrideWithValue(_repo),
          currentUserProvider.overrideWith((ref) async => null),
          ordersProvider.overrideWith(EmptyOrders.new),
          ...overrides,
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
          home: child,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

final _repo = FakeHelpRepo(
  cats: [
    cat('account', 'Hesabım', 6),
    cat('orders', 'Siparişlerim', 6),
    cat('returns', 'İadeler', 6),
    cat('payment', 'Ödeme', 6),
  ],
  one: const HelpArticleDto(
    slug: 'reset', title: 'Şifre nasıl sıfırlanır', body: '## Adımlar\n\n- Birinci\n- İkinci',
  ),
  results: const [
    HelpSearchResultDto(slug: 'reset', title: '**Şifre**', snippet: '...şifre sıfırla...', categorySlug: 'account'),
  ],
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('help_category_card 1440 light', (tester) async {
    await _pump(
      tester,
      Scaffold(body: Center(child: SizedBox(width: 360, child: HelpCategoryCard(category: cat('account', 'Hesabım', 6))))),
      height: 200,
    );
    await expectLater(
      find.byType(HelpCategoryCard),
      matchesGoldenFile('goldens/help_category_card_light.png'),
    );
  });

  for (final b in Brightness.values) {
    final name = b == Brightness.dark ? 'dark' : 'light';
    testWidgets('help_index 1440 $name', (tester) async {
      await _pump(tester, const HelpIndexScreen(), brightness: b);
      await expectLater(
        find.byType(HelpIndexScreen),
        matchesGoldenFile('goldens/help_index_1440_$name.png'),
      );
    });
  }

  testWidgets('help_index 375 light', (tester) async {
    await _pump(tester, const HelpIndexScreen(), width: 375, height: 900);
    await expectLater(
      find.byType(HelpIndexScreen),
      matchesGoldenFile('goldens/help_index_375_light.png'),
    );
  });

  testWidgets('help_article 1440 light', (tester) async {
    await _pump(tester, const HelpArticleScreen(slug: 'reset'));
    await expectLater(
      find.byType(HelpArticleScreen),
      matchesGoldenFile('goldens/help_article_1440_light.png'),
    );
  });

  testWidgets('help_search 1440 light', (tester) async {
    await _pump(tester, const HelpSearchScreen(query: 'şifre'));
    await expectLater(
      find.byType(HelpSearchScreen),
      matchesGoldenFile('goldens/help_search_1440_light.png'),
    );
  });

  testWidgets('contact_form 1440 light', (tester) async {
    await _pump(tester, const ContactFormScreen());
    await expectLater(
      find.byType(ContactFormScreen),
      matchesGoldenFile('goldens/contact_form_1440_light.png'),
    );
  });

  testWidgets('contact_form 375 light', (tester) async {
    await _pump(tester, const ContactFormScreen(), width: 375, height: 900);
    await expectLater(
      find.byType(ContactFormScreen),
      matchesGoldenFile('goldens/contact_form_375_light.png'),
    );
  });
}
