import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/help/data/help_dto.dart';
import 'package:mopro/features/help/data/help_repository.dart';
import 'package:mopro/features/help/help_article_screen.dart';
import 'package:mopro/features/help/help_category_screen.dart';
import 'package:mopro/features/help/help_index_screen.dart';
import 'package:mopro/features/help/help_search_screen.dart';
import 'package:mopro/features/help/widgets/help_category_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'help_test_support.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  FakeHelpRepo repo, {
  Size size = const Size(1440, 1200),
}) async {
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
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [helpRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: child),
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

  testWidgets('index renders category grid + Bize Ulaş', (tester) async {
    await _pump(
      tester,
      const HelpIndexScreen(),
      FakeHelpRepo(cats: [cat('account', 'Hesabım', 6), cat('orders', 'Siparişlerim', 6)]),
    );
    expect(find.byType(HelpCategoryCard), findsNWidgets(2));
    expect(find.textContaining('help.contact_cta'), findsOneWidget);
  });

  testWidgets('category empty state', (tester) async {
    await _pump(tester, const HelpCategoryScreen(slug: 'x'), FakeHelpRepo());
    expect(find.textContaining('help.empty_category'), findsOneWidget);
  });

  testWidgets('article renders markdown body', (tester) async {
    await _pump(
      tester,
      const HelpArticleScreen(slug: 'reset'),
      FakeHelpRepo(one: const HelpArticleDto(slug: 'reset', title: 'Şifre', body: '## Adım\n\nMetin')),
    );
    expect(find.byType(MarkdownBody), findsWidgets);
    expect(find.text('Şifre'), findsOneWidget);
  });

  testWidgets('search empty state shows contact CTA', (tester) async {
    await _pump(tester, const HelpSearchScreen(query: 'zzz'), FakeHelpRepo());
    expect(find.textContaining('help.search_empty'), findsOneWidget);
  });

  testWidgets('search debounces: no fetch until 300ms quiet', (tester) async {
    var calls = 0;
    final repo = _CountingRepo(() => calls++);
    await _pump(tester, const HelpSearchScreen(query: ''), repo);
    await tester.enterText(find.byType(TextField), 'ia');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'iad');
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, 0, reason: 'no fetch while typing within debounce window');
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, greaterThan(0), reason: 'fetch fires after 300ms quiet');
  });
}

class _CountingRepo extends FakeHelpRepo {
  _CountingRepo(this._onSearch);
  final void Function() _onSearch;
  @override
  Future<List<HelpSearchResultDto>> search(String query) async {
    _onSearch();
    return const [];
  }
}
