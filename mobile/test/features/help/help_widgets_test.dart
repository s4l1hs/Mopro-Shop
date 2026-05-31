import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/help/data/help_repository.dart';
import 'package:mopro/features/help/widgets/contact_form_content.dart';
import 'package:mopro/features/help/widgets/help_category_card.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'help_test_support.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('HelpCategoryCard shows title, count, icon', (tester) async {
    await tester.pumpWidget(
      _wrap(HelpCategoryCard(category: cat('account', 'Hesabım', 6))),
    );
    await tester.pump();
    expect(find.text('Hesabım'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.textContaining('help.article_count'), findsOneWidget);
  });

  group('ContactFormContent', () {
    List<Override> overrides(FakeHelpRepo repo) => [
          helpRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWith((ref) async => null),
          ordersProvider.overrideWith(EmptyOrders.new),
        ];

    testWidgets('submit gated until required fields valid, then succeeds',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeHelpRepo();
      await tester.pumpWidget(
        _wrap(
          const SingleChildScrollView(child: ContactFormContent()),
          overrides: overrides(repo),
        ),
      );
      await tester.pump();

      final submit = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(submit.onPressed, isNull); // disabled initially

      await tester.enterText(find.byType(TextField).at(0), 'a@b.co'); // email
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('help.ticket_cat_other').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'Subject'); // subject
      await tester.enterText(find.byType(TextField).at(2), 'My message body'); // body
      await tester.pump();

      final submit2 = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(submit2.onPressed, isNotNull); // enabled

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(repo.created, isNotNull);
      expect(find.textContaining('contact_ticket_no'), findsOneWidget); // success state
    });

    testWidgets('article subject pre-fill', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SingleChildScrollView(
            child: ContactFormContent(articleSlug: 'x', articleTitle: 'İade nasıl'),
          ),
          overrides: overrides(FakeHelpRepo()),
        ),
      );
      await tester.pump();
      // Subject field carries the article-subject key (raw under test).
      expect(
        find.textContaining('contact_article_subject', findRichText: true),
        findsWidgets,
      );
    });
  });
}
