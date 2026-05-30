import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/catalog/pdp/reviews/reviews_provider.dart';

/// Canned adapter for the reviews endpoints. Serves [total] generated reviews
/// paged by kReviewsPageSize, varies the first item by sort so refetches are
/// observable, and lets tests force the helpful POST to fail.
class _ReviewsAdapter implements HttpClientAdapter {
  _ReviewsAdapter();
  final int total = 12;
  bool failHelpful = false;
  int helpfulPostCount = 0;

  Map<String, dynamic> _review(
    int id, {
    int rating = 4,
    int helpful = 0,
    bool voted = false,
  }) =>
      {
        'id': id,
        'userId': 100 + id,
        'rating': rating,
        'title': 'T$id',
        'body': 'B$id',
        'helpfulCount': helpful,
        'votedByCurrentUser': voted,
        'createdAt': '2026-01-0${(id % 9) + 1}T00:00:00Z',
      };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path.contains('/helpful')) {
      helpfulPostCount++;
      if (failHelpful) {
        return ResponseBody.fromString(
          '{"error":"boom"}',
          500,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      // Return a server-authoritative count distinct from the optimistic guess
      // so the reconcile step is observable.
      return ResponseBody.fromString(
        jsonEncode({'voted': true, 'helpfulCount': 42}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // GET list
    final q = options.uri.queryParameters;
    final sort = q['sort'] ?? 'newest';
    final page = int.tryParse(q['page'] ?? '1') ?? 1;
    final start = (page - 1) * kReviewsPageSize;
    final items = <Map<String, dynamic>>[];
    for (var i = start; i < total && i < start + kReviewsPageSize; i++) {
      // First item of a "highest" sort gets a marker id so refetch is provable.
      final id = (sort == 'highest' && i == 0) ? 999 : i + 1;
      items.add(_review(id, helpful: i));
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

ProviderContainer _container(_ReviewsAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  final c = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
  addTearDown(c.dispose);
  return c;
}

/// Pumps microtasks/futures until the predicate holds (bounded).
Future<void> _settle(
  ProviderContainer c,
  bool Function(ReviewsState) until,
) async {
  for (var i = 0; i < 50; i++) {
    if (until(c.read(reviewsNotifierProvider(1)))) return;
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('initial load: loading then items + summary populated', () async {
    final c = _container(_ReviewsAdapter());
    // Reading triggers build() → microtask _loadInitial.
    expect(c.read(reviewsNotifierProvider(1)).loading, isTrue);
    await _settle(c, (s) => !s.loading);
    final s = c.read(reviewsNotifierProvider(1));
    expect(s.loading, isFalse);
    expect(s.items.length, kReviewsPageSize);
    expect(s.total, 12);
    expect(s.summary?.totalCount, 12);
    expect(s.summary?.distribution[5], 4);
    expect(s.page, 1);
  });

  test('setSort refetches with new sort and resets to page 1', () async {
    final c = _container(_ReviewsAdapter());
    await _settle(c, (s) => !s.loading);
    final notifier = c.read(reviewsNotifierProvider(1).notifier);

    await notifier.setSort(ReviewSort.highest);
    final s = c.read(reviewsNotifierProvider(1));
    expect(s.sort, ReviewSort.highest);
    expect(s.page, 1);
    expect(s.items.first.id, 999); // marker proves a refetch with the new sort
  });

  test('loadMore appends page 2 and toggles loadingMore', () async {
    final c = _container(_ReviewsAdapter());
    await _settle(c, (s) => !s.loading);
    final notifier = c.read(reviewsNotifierProvider(1).notifier);

    expect(c.read(reviewsNotifierProvider(1)).hasMore, isTrue);
    await notifier.loadMore();
    final s = c.read(reviewsNotifierProvider(1));
    expect(s.items.length, 12); // 10 + 2
    expect(s.page, 2);
    expect(s.loadingMore, isFalse);
    expect(s.hasMore, isFalse);
  });

  test('toggleHelpful optimistic then reconciles with server value', () async {
    final c = _container(_ReviewsAdapter());
    await _settle(c, (s) => !s.loading);
    final notifier = c.read(reviewsNotifierProvider(1).notifier);
    final first = c.read(reviewsNotifierProvider(1)).items.first;

    final ok = await notifier.toggleHelpful(first.id);
    expect(ok, isTrue);
    final updated = c
        .read(reviewsNotifierProvider(1))
        .items
        .firstWhere((r) => r.id == first.id);
    expect(updated.votedByCurrentUser, isTrue);
    expect(updated.helpfulCount, 42); // server-authoritative, not optimistic +1
  });

  test('toggleHelpful rolls back on server error and returns false', () async {
    final adapter = _ReviewsAdapter()..failHelpful = true;
    final c = _container(adapter);
    await _settle(c, (s) => !s.loading);
    final notifier = c.read(reviewsNotifierProvider(1).notifier);
    final first = c.read(reviewsNotifierProvider(1)).items.first;
    final beforeCount = first.helpfulCount;
    final beforeVoted = first.votedByCurrentUser;

    final ok = await notifier.toggleHelpful(first.id);
    expect(ok, isFalse);
    final after = c
        .read(reviewsNotifierProvider(1))
        .items
        .firstWhere((r) => r.id == first.id);
    expect(after.helpfulCount, beforeCount);
    expect(after.votedByCurrentUser, beforeVoted);
  });

  test('concurrent toggleHelpful calls converge consistently', () async {
    final c = _container(_ReviewsAdapter());
    await _settle(c, (s) => !s.loading);
    final notifier = c.read(reviewsNotifierProvider(1).notifier);
    final first = c.read(reviewsNotifierProvider(1)).items.first;

    await Future.wait([
      notifier.toggleHelpful(first.id),
      notifier.toggleHelpful(first.id),
    ]);
    // Server is authoritative (returns count=42, voted=true); both calls reconcile
    // to the same final value with no double-application.
    final after = c
        .read(reviewsNotifierProvider(1))
        .items
        .firstWhere((r) => r.id == first.id);
    expect(after.helpfulCount, 42);
    expect(after.votedByCurrentUser, isTrue);
  });
}
