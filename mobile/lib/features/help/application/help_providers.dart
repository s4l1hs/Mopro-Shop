import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/help/data/help_dto.dart';
import 'package:mopro/features/help/data/help_repository.dart';

/// Help categories — cached for the session (content changes rarely).
final helpCategoriesProvider = FutureProvider<List<HelpCategoryDto>>((ref) {
  return ref.watch(helpRepositoryProvider).categories();
});

/// Articles in a category, keyed by category slug.
final helpArticlesProvider =
    FutureProviderFamily<List<HelpArticleDto>, String>((ref, categorySlug) {
  return ref.watch(helpRepositoryProvider).articles(categorySlug);
});

/// Single article detail, keyed by article slug.
final helpArticleProvider =
    FutureProviderFamily<HelpArticleDto, String>((ref, slug) {
  return ref.watch(helpRepositoryProvider).article(slug);
});

/// Search results, keyed by query. Empty query short-circuits to no results.
final helpSearchProvider =
    FutureProviderFamily<List<HelpSearchResultDto>, String>((ref, query) {
  if (query.trim().isEmpty) return Future.value(const []);
  return ref.watch(helpRepositoryProvider).search(query);
});
