import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';

class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.imageUrl,
    required this.deepLink,
  });
  final int id;
  final String imageUrl;
  final String deepLink;
}

class HomeRail {
  const HomeRail({required this.key, required this.title});
  final String key;
  final String title;
}

/// One circular tile in the home-screen "mood stories" strip.
class HomeMoodStory {
  const HomeMoodStory({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.deepLink,
  });
  final int id;
  final String title;
  final String imageUrl;
  final String deepLink;
}

/// Fetches banner carousel data from GET /home/banners.
final homeBannersProvider = FutureProvider.autoDispose<List<HomeBanner>>(
  (ref) async {
    final dio = ref.watch(dioProvider);
    final resp = await dio.get<Map<String, dynamic>>('/home/banners');
    final data = (resp.data?['data'] as List<dynamic>?) ?? [];
    return data.map((e) {
      final m = e as Map<String, dynamic>;
      return HomeBanner(
        id: m['id'] as int,
        imageUrl: m['image_url'] as String,
        deepLink: m['deep_link'] as String? ?? '/',
      );
    }).toList();
  },
);

/// Fetches server-driven rail order from `GET /home/rails?layout=<layout>`.
///
/// The `layout` hint (`'desktop'` or `'mobile'`) is computed at the screen from
/// the breakpoint and passed into the family key (§6.3). The backend surfaces up
/// to 6 rails for `desktop` and up to 3 otherwise.
final homeRailsProvider =
    FutureProvider.autoDispose.family<List<HomeRail>, String>(
  (ref, layout) async {
    final dio = ref.watch(dioProvider);
    try {
      final resp = await dio.get<Map<String, dynamic>>(
        '/home/rails',
        queryParameters: {'layout': layout},
      );
      final data = (resp.data?['data'] as List<dynamic>?) ?? [];
      return data.map((e) {
        final m = e as Map<String, dynamic>;
        return HomeRail(key: m['key'] as String, title: m['title'] as String);
      }).toList();
    } on DioException catch (_) {
      // Fallback to default order if endpoint fails.
      const fallback = [
        HomeRail(key: 'recommended', title: 'Sizin için seçtiklerimiz'),
        HomeRail(key: 'bestseller', title: 'Çok satanlar'),
        HomeRail(key: 'newest', title: 'Yeni gelenler'),
      ];
      return fallback;
    }
  },
);

/// Fetches mood-story tiles from GET /home/stories. Returns an empty list on
/// any error so the home screen can simply omit the strip rather than show a
/// broken state.
final homeMoodStoriesProvider = FutureProvider.autoDispose<List<HomeMoodStory>>(
  (ref) async {
    final dio = ref.watch(dioProvider);
    try {
      final resp = await dio.get<Map<String, dynamic>>('/home/stories');
      final data = (resp.data?['data'] as List<dynamic>?) ?? [];
      return data.map((e) {
        final m = e as Map<String, dynamic>;
        return HomeMoodStory(
          id: m['id'] as int,
          title: m['title'] as String,
          imageUrl: m['image_url'] as String,
          deepLink: m['deep_link'] as String? ?? '/',
        );
      }).toList();
    } on DioException catch (_) {
      return const <HomeMoodStory>[];
    }
  },
);

/// Trending search queries for the animated search pill placeholder.
final trendingSearchesProvider = FutureProvider.autoDispose<List<String>>(
  (ref) async {
    final dio = ref.watch(dioProvider);
    try {
      final resp = await dio.get<Map<String, dynamic>>('/search/trending');
      final data = (resp.data?['data'] as List<dynamic>?) ?? [];
      return data.cast<String>();
    } on DioException catch (_) {
      return const ['Akıllı telefon', 'Laptop', 'Giyim', 'Spor ayakkabı'];
    }
  },
);
