import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/auth/widgets/login_required.dart';
import 'package:mopro/features/catalog/pdp/reviews/pdp_reviews_tab.dart';
import 'package:mopro/features/catalog/pdp/reviews/rating_distribution_histogram.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_row.dart';
import 'package:mopro/features/catalog/pdp/reviews/reviews_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../_support/test_harness.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._initial);
  final AuthState _initial;
  @override
  Future<AuthState> build() async => _initial;
}

/// Canned reviews adapter for widget tests.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.total = 12});
  final int total;
  bool failGet = false;
  bool failHelpful = false;
  String? lastSort;
  int helpfulPosts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path.contains('/helpful')) {
      helpfulPosts++;
      if (failHelpful) {
        throw DioException(requestOptions: options, error: 'boom');
      }
      return ResponseBody.fromString(
        jsonEncode({'voted': true, 'helpfulCount': 99}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (failGet) {
      return ResponseBody.fromString(
        '{}',
        500,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final q = options.uri.queryParameters;
    lastSort = q['sort'];
    final page = int.tryParse(q['page'] ?? '1') ?? 1;
    final start = (page - 1) * kReviewsPageSize;
    final items = <Map<String, dynamic>>[];
    for (var i = start; i < total && i < start + kReviewsPageSize; i++) {
      items.add({
        'id': i + 1,
        'userId': 100 + i,
        'rating': 1 + (i % 5),
        'title': 'Title$i',
        'body': 'Body$i',
        'helpfulCount': i,
        'votedByCurrentUser': false,
        'createdAt': '2026-01-0${(i % 9) + 1}T00:00:00Z',
      });
    }
    return ResponseBody.fromString(
      jsonEncode({
        'items': items,
        'total': total,
        'page': page,
        'pageSize': kReviewsPageSize,
        'summary': {
          'average': 4.2,
          'distribution': {'1': 1, '2': 1, '3': 2, '4': 4, '5': 4},
          'totalCount': total,
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required _Adapter adapter,
  AuthState auth = const AuthUnauthenticated(),
  Size size = const Size(420, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dioProvider.overrideWithValue(dio),
        authNotifierProvider.overrideWith(() => _FakeAuth(auth)),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(body: PdpReviewsTab(productId: 1)),
      ),
    ),
  );
  // authNotifierProvider is lazy; pre-warm it so the guest/authed gate sees a
  // resolved value at tap time (in the real app it is watched at startup).
  final container = ProviderScope.containerOf(
    tester.element(find.byType(PdpReviewsTab)),
  );
  await container.read(authNotifierProvider.future);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  group('RatingDistributionHistogram', () {
    testWidgets('bar widths match the seeded distribution', (tester) async {
      const summary = ReviewsSummary(
        average: 4,
        distribution: {1: 0, 2: 0, 3: 0, 4: 5, 5: 5},
        totalCount: 10,
      );
      await pumpTrendyolApp(
        tester,
        const RatingDistributionHistogram(summary: summary),
      );
      final bars = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .toList();
      // 5 bars, 5★ first. 5★=0.5, 4★=0.5, 3★/2★/1★=0.
      expect(bars.length, 5);
      expect(bars[0].widthFactor, closeTo(0.5, 1e-9)); // 5★
      expect(bars[1].widthFactor, closeTo(0.5, 1e-9)); // 4★
      expect(bars[4].widthFactor, 0); // 1★
    });

    testWidgets('empty state renders the empty copy and no bars', (tester) async {
      const summary = ReviewsSummary(
        average: 0,
        distribution: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
        totalCount: 0,
      );
      await pumpTrendyolApp(
        tester,
        const RatingDistributionHistogram(summary: summary),
      );
      expect(find.text('reviews.empty'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNothing);
    });
  });

  group('PdpReviewsTab', () {
    testWidgets('renders histogram + reviews + Daha fazla when more pages exist',
        (tester) async {
      await _pumpTab(tester, adapter: _Adapter());
      expect(find.byType(RatingDistributionHistogram), findsOneWidget);
      expect(find.byType(ReviewRow), findsNWidgets(kReviewsPageSize));
      expect(find.text('reviews.load_more'), findsOneWidget);
    });

    testWidgets('sort dropdown selection triggers a refetch with the new sort',
        (tester) async {
      final adapter = _Adapter();
      await _pumpTab(tester, adapter: adapter);
      expect(adapter.lastSort, 'newest');

      // Open the sort menu (anchor shows the current sort key) and pick highest.
      await tester.tap(find.text('reviews.sort_newest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('reviews.sort_highest').last);
      await tester.pumpAndSettle();

      expect(adapter.lastSort, 'highest');
    });

    testWidgets('guest tapping Faydalı opens the login presenter',
        (tester) async {
      await _pumpTab(tester, adapter: _Adapter(total: 5));
      await tester.tap(find.byIcon(Icons.thumb_up_alt_outlined).first);
      await tester.pumpAndSettle();
      expect(find.byType(LoginRequired), findsOneWidget);
    });

    testWidgets('authed tap increments optimistically then reconciles',
        (tester) async {
      final adapter = _Adapter(total: 5);
      await _pumpTab(tester, adapter: adapter, auth: const AuthAuthenticated());
      expect(find.byType(ReviewRow), findsNWidgets(5));
      expect(find.byType(FilledButton), findsNothing); // none voted yet

      await tester.tap(find.byIcon(Icons.thumb_up_alt_outlined).first);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      // The POST reached the server and the tapped review is now voted (filled).
      expect(adapter.helpfulPosts, 1);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('authed tap rolls back + shows SnackBar on server error',
        (tester) async {
      final adapter = _Adapter(total: 5)..failHelpful = true;
      await _pumpTab(
        tester,
        adapter: adapter,
        auth: const AuthAuthenticated(),
      );
      await tester.tap(find.byIcon(Icons.thumb_up_alt_outlined).first);
      // runAsync drives the real dio future (the POST rejects); a plain pump
      // can't flush it. Then pump the SnackBar frame, staying under its 4s
      // auto-dismiss (pumpAndSettle would advance past it).
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(); // build the scheduled SnackBar
      await tester.pump(const Duration(milliseconds: 300)); // entrance animation
      expect(find.text('reviews.action_failed'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('Daha fazla appends page 2 and hides when all loaded',
        (tester) async {
      await _pumpTab(tester, adapter: _Adapter());
      expect(find.byType(ReviewRow), findsNWidgets(kReviewsPageSize));
      await tester.tap(find.text('reviews.load_more'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewRow), findsNWidgets(12));
      expect(find.text('reviews.load_more'), findsNothing);
    });

    testWidgets('no Daha fazla button when the first page is the whole set',
        (tester) async {
      await _pumpTab(tester, adapter: _Adapter(total: 5));
      expect(find.byType(ReviewRow), findsNWidgets(5));
      expect(find.text('reviews.load_more'), findsNothing);
    });

    testWidgets('initial load error shows retry', (tester) async {
      final adapter = _Adapter()..failGet = true;
      await _pumpTab(tester, adapter: adapter);
      expect(find.text('reviews.load_error'), findsOneWidget);
      expect(find.text('common.retry'), findsOneWidget);
    });
  });
}
