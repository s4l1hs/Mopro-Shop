import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/providers/home_provider.dart';
import 'package:mopro/features/catalog/widgets/mood_stories_strip.dart';

import '../../../_support/test_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  required AsyncValue<List<HomeMoodStory>> state,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeMoodStoriesProvider.overrideWith(
          (ref) async {
            // Mirror the AsyncValue passed in so the widget can resolve to
            // loading / error / data deterministically.
            return state.when(
              data: (d) => d,
              loading: () => Future<List<HomeMoodStory>>.delayed(
                const Duration(seconds: 10),
                () => const <HomeMoodStory>[],
              ),
              error: (e, _) => Future<List<HomeMoodStory>>.error(e),
            );
          },
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: MoodStoriesStrip()),
      ),
    ),
  );
}

void main() {
  setUpAll(initTestEnv);

  group('MoodStoriesStrip', () {
    testWidgets('collapses to empty when provider returns []', (tester) async {
      await _pump(tester, state: const AsyncValue.data(<HomeMoodStory>[]));
      await tester.pump();
      // SizedBox.shrink — no list, no images.
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('collapses to empty on error', (tester) async {
      await _pump(
        tester,
        state: AsyncValue.error(Exception('boom'), StackTrace.current),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('renders one tile per story with title text', (tester) async {
      await _pump(
        tester,
        state: const AsyncValue.data([
          HomeMoodStory(
            id: 1,
            title: 'Yeni Sezon',
            imageUrl: 'https://example.test/a.png',
            deepLink: '/categories?mood=new_season',
          ),
          HomeMoodStory(
            id: 2,
            title: 'İndirimler',
            imageUrl: 'https://example.test/b.png',
            deepLink: '/categories?mood=deals',
          ),
        ]),
      );
      // Provider resolves on the next frame.
      await tester.pump();
      expect(find.text('Yeni Sezon'), findsOneWidget);
      expect(find.text('İndirimler'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
