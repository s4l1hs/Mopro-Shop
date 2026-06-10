import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';

/// Source of truth for a listing's [PlpFilters], keyed by a listing id:
/// a numeric category id as a string (`'42'`), or the search sentinel
/// `'_search:<query>'` so search results share the same substrate.
///
/// Hydrated from the URL on screen entry and written to by any filter UI
/// (mobile sort/filter sheets today; the 5b sidebar later). The screen mirrors
/// changes back into the URL (debounced) so state is shareable and survives
/// browser back/forward.
class PlpFiltersNotifier extends FamilyNotifier<PlpFilters, String> {
  @override
  PlpFilters build(String arg) => const PlpFilters();

  /// Replace the whole filter state (used by URL hydration + the sidebar).
  // ignore: use_setters_to_change_properties — `set` reads clearer than a setter here
  void set(PlpFilters next) => state = next;

  /// Apply a partial change.
  void update(PlpFilters Function(PlpFilters) fn) => state = fn(state);

  /// Convenience for the sort sheet.
  void setSort(PlpSort sort) => state = state.copyWith(sort: sort, page: 1);

  /// PLP-13: toggle a value within an attribute slug (e.g. `renk` / `Siyah`).
  /// Copies the map (immutable state) and removes a slug once empty. Resets page.
  void toggleAttr(String slug, String value) {
    final next = <String, List<String>>{
      for (final e in state.attrs.entries) e.key: List<String>.from(e.value),
    };
    final list = next.putIfAbsent(slug, () => <String>[]);
    if (list.contains(value)) {
      list.remove(value);
    } else {
      list.add(value);
    }
    if (list.isEmpty) next.remove(slug);
    state = state.copyWith(attrs: next, page: 1);
  }
}

final plpFiltersProvider =
    NotifierProviderFamily<PlpFiltersNotifier, PlpFilters, String>(
  PlpFiltersNotifier.new,
);

/// Stable key for a category listing.
String plpKeyForCategory(int categoryId) => '$categoryId';

/// Stable key for a search listing.
String plpKeyForSearch(String query) => '_search:$query';
