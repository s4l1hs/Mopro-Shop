import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/shell/search_suggestions_dropdown.dart';
import 'package:mopro_api/mopro_api.dart';

import '../_support/test_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  Size size = const Size(720, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: 480, child: child),
        ),
      ),
    ),
  );
}

Category _cat(int id, String name) => Category(
      id: id,
      name: name,
      slug: name.toLowerCase(),
      commissionPctBps: 1000,
    );

void main() {
  setUpAll(initTestEnv);

  group('SearchSuggestionsDropdown — section visibility', () {
    testWidgets('renders all three sections when populated', (tester) async {
      await _pump(
        tester,
        child: SearchSuggestionsDropdown(
          recentSearches: const ['ayakkabı', 'kazak'],
          trendingSearches: const AsyncSnapshot<List<String>>.withData(
            ConnectionState.done,
            ['laptop', 'telefon', 'koltuk'],
          ),
          categories: [_cat(1, 'Giyim'), _cat(2, 'Elektronik')],
          onSelectRecent: (_) {},
          onSelectTrending: (_) {},
          onSelectCategory: (_) {},
          onRemoveRecent: (_) {},
        ),
      );
      expect(find.text('ayakkabı'), findsOneWidget);
      expect(find.text('laptop'), findsOneWidget);
      expect(find.text('Giyim'), findsOneWidget);
    });

    testWidgets('collapses entirely when all sections empty', (tester) async {
      await _pump(
        tester,
        child: const SearchSuggestionsDropdown(
          recentSearches: [],
          trendingSearches: AsyncSnapshot<List<String>>.withData(
            ConnectionState.done,
            [],
          ),
          categories: [],
          onSelectRecent: _noopStr,
          onSelectTrending: _noopStr,
          onSelectCategory: _noopInt,
          onRemoveRecent: _noopStr,
        ),
      );
      // Empty sections should render as SizedBox.shrink with no list content
      // (no section headers, no rows).
      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.byIcon(Icons.history), findsNothing);
      expect(find.byIcon(Icons.trending_up), findsNothing);
      expect(find.byIcon(Icons.category_outlined), findsNothing);
    });

    testWidgets(
        'hides trending header when trending empty but recent populated',
        (tester) async {
      await _pump(
        tester,
        child: SearchSuggestionsDropdown(
          recentSearches: const ['ayakkabı'],
          trendingSearches: const AsyncSnapshot<List<String>>.withData(
            ConnectionState.done,
            [],
          ),
          categories: const [],
          onSelectRecent: (_) {},
          onSelectTrending: (_) {},
          onSelectCategory: (_) {},
          onRemoveRecent: (_) {},
        ),
      );
      expect(find.text('ayakkabı'), findsOneWidget);
      // Trending header should not be present when trending list is empty.
      expect(find.byIcon(Icons.trending_up), findsNothing);
    });

    testWidgets('shows skeleton rows while trending loading', (tester) async {
      await _pump(
        tester,
        child: SearchSuggestionsDropdown(
          recentSearches: const [],
          trendingSearches: const AsyncSnapshot<List<String>>.waiting(),
          categories: const [],
          onSelectRecent: (_) {},
          onSelectTrending: (_) {},
          onSelectCategory: (_) {},
          onRemoveRecent: (_) {},
        ),
      );
      // Skeletons render where the trending list would go — no trending-up
      // icons yet because we're still loading.
      expect(find.byIcon(Icons.trending_up), findsNothing);
      // The dropdown's outer Material wrapper renders, distinct from the
      // Scaffold's. Lookup by descendant ensures we hit the dropdown one.
      expect(
        find.descendant(
          of: find.byType(SearchSuggestionsDropdown),
          matching: find.byType(Material),
        ),
        findsOneWidget,
      );
    });
  });

  group('SearchSuggestionsDropdown — callbacks', () {
    testWidgets('tapping a recent row invokes onSelectRecent', (tester) async {
      String? picked;
      await _pump(
        tester,
        child: SearchSuggestionsDropdown(
          recentSearches: const ['ayakkabı'],
          trendingSearches: const AsyncSnapshot<List<String>>.withData(
            ConnectionState.done,
            [],
          ),
          categories: const [],
          onSelectRecent: (q) => picked = q,
          onSelectTrending: (_) {},
          onSelectCategory: (_) {},
          onRemoveRecent: (_) {},
        ),
      );
      await tester.tap(find.text('ayakkabı'));
      await tester.pump();
      expect(picked, 'ayakkabı');
    });

    testWidgets('tapping × on recent row invokes onRemoveRecent',
        (tester) async {
      String? removed;
      await _pump(
        tester,
        child: SearchSuggestionsDropdown(
          recentSearches: const ['ayakkabı'],
          trendingSearches: const AsyncSnapshot<List<String>>.withData(
            ConnectionState.done,
            [],
          ),
          categories: const [],
          onSelectRecent: (_) {},
          onSelectTrending: (_) {},
          onSelectCategory: (_) {},
          onRemoveRecent: (q) => removed = q,
        ),
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(removed, 'ayakkabı');
    });

    testWidgets('tapping a category row invokes onSelectCategory with id',
        (tester) async {
      int? id;
      await _pump(
        tester,
        child: SearchSuggestionsDropdown(
          recentSearches: const [],
          trendingSearches: const AsyncSnapshot<List<String>>.withData(
            ConnectionState.done,
            [],
          ),
          categories: [_cat(42, 'Spor')],
          onSelectRecent: (_) {},
          onSelectTrending: (_) {},
          onSelectCategory: (i) => id = i,
          onRemoveRecent: (_) {},
        ),
      );
      await tester.tap(find.text('Spor'));
      await tester.pump();
      expect(id, 42);
    });
  });

  group('SearchSuggestionsDropdown — goldens', () {
    testWidgets('populated three-section view', (tester) async {
      await _pump(
        tester,
        child: SearchSuggestionsDropdown(
          recentSearches: const ['ayakkabı', 'kazak'],
          trendingSearches: const AsyncSnapshot<List<String>>.withData(
            ConnectionState.done,
            ['laptop', 'telefon', 'koltuk'],
          ),
          categories: [
            _cat(1, 'Giyim'),
            _cat(2, 'Elektronik'),
            _cat(3, 'Ev & Yaşam'),
          ],
          onSelectRecent: (_) {},
          onSelectTrending: (_) {},
          onSelectCategory: (_) {},
          onRemoveRecent: (_) {},
        ),
      );
      await expectLater(
        find.byType(SearchSuggestionsDropdown),
        matchesGoldenFile('goldens/search_suggestions_populated.png'),
      );
    });
  });
}

void _noopStr(String _) {}
void _noopInt(int _) {}
