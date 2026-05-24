import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kFavKey = 'mopro_favorites';

class FavoritesNotifier extends StateNotifier<Set<int>> {
  FavoritesNotifier(SharedPreferences prefs)
      : _prefs = prefs,
        super(_load(prefs));

  final SharedPreferences _prefs;

  static Set<int> _load(SharedPreferences p) {
    final raw = p.getStringList(_kFavKey) ?? [];
    return raw.map(int.parse).toSet();
  }

  void toggle(int productId) {
    final next = Set<int>.from(state);
    if (next.contains(productId)) {
      next.remove(productId);
    } else {
      next.add(productId);
    }
    state = next;
    _prefs.setStringList(_kFavKey, next.map((e) => e.toString()).toList());
  }

  bool isFavorite(int productId) => state.contains(productId);
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<int>>((ref) {
  return FavoritesNotifier(ref.watch(sharedPreferencesProvider));
});

final isFavoriteProvider = Provider.family<bool, int>((ref, id) {
  return ref.watch(favoritesProvider).contains(id);
});
