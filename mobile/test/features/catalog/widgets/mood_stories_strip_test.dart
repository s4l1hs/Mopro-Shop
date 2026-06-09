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
  // Size via tester.view (dpr=1) so the breakpoint resolves reliably to mobile
  // — setSurfaceSize(390) resolves to tablet here and would hit the grid branch.
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

    // G-2: the gradient ring is exactly 72dp (Trendyol spec), not the legacy
    // 64+6 = 70dp.
    testWidgets('avatar ring is exactly 72dp', (tester) async {
      await _pump(
        tester,
        state: const AsyncValue.data([
          HomeMoodStory(
            id: 1,
            title: 'Yeni Sezon',
            imageUrl: 'https://example.test/a.png',
            deepLink: '/categories?mood=new_season',
          ),
        ]),
      );
      await tester.pump();
      final ring = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration! as BoxDecoration).gradient != null,
      );
      expect(ring, findsOneWidget);
      expect(tester.getSize(ring), const Size(72, 72));
    });

    // G-2: a horizontal edge-fade ShaderMask wraps the scroller (mirrors the
    // mega-menu bar).
    testWidgets('edge-fade ShaderMask wraps the horizontal scroller',
        (tester) async {
      await _pump(
        tester,
        state: const AsyncValue.data([
          HomeMoodStory(
            id: 1,
            title: 'Yeni Sezon',
            imageUrl: 'https://example.test/a.png',
            deepLink: '/categories?mood=new_season',
          ),
        ]),
      );
      await tester.pump();
      expect(
        find.ancestor(
          of: find.byType(ListView),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
    });
  });
}
