import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
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

  /// Merges server-side favorite IDs into the local set (FAV-02 down-sync) — a
  /// union, so a server pull never drops a local-only add. Persists + notifies
  /// only when the set actually grows.
  void mergeServer(Iterable<int> ids) {
    final next = Set<int>.from(state)..addAll(ids);
    if (next.length == state.length) return;
    state = next;
    _prefs.setStringList(_kFavKey, next.map((e) => e.toString()).toList());
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<int>>((ref) {
  return FavoritesNotifier(ref.watch(sharedPreferencesProvider));
});

/// Pulls the authed user's server-side favorites (`GET /favorites`) and merges
/// them into the local set — the FAV-02 down-sync that makes favorites
/// cross-device. Best-effort: any failure is swallowed so it never blocks auth
/// or launch. Uses the auth-interceptored Dio.
Future<void> hydrateFavoritesFromServer(Ref ref) async {
  try {
    final dio = ref.read(dioProvider);
    final resp = await dio.get<Map<String, dynamic>>('/favorites');
    final ids = ((resp.data?['product_ids'] as List<dynamic>?) ?? const [])
        .map((e) => (e as num).toInt());
    ref.read(favoritesProvider.notifier).mergeServer(ids);
  } on DioException {
    // best-effort — local set stays as-is
  } catch (_) {
    // best-effort
  }
}

final isFavoriteProvider = Provider.family<bool, int>((ref, id) {
  return ref.watch(favoritesProvider).contains(id);
});
