import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kFavKey = 'mopro_favorites';

/// FAV-07: price-at-favorite snapshots (`{productId: priceMinor}`), so the
/// favorites surface can show a "fiyatı düştü since you saved it" cue. Kept
/// device-local alongside the favorites set itself — the snapshot is captured
/// when the user toggles the heart, the only moment we know the price they saw.
const _kFavPriceKey = 'mopro_favorite_prices';

class FavoritesNotifier extends StateNotifier<Set<int>> {
  FavoritesNotifier(SharedPreferences prefs)
      : _prefs = prefs,
        _prices = _loadPrices(prefs),
        super(_load(prefs));

  final SharedPreferences _prefs;

  /// Price the user saw at favorite-time, per product id. Not part of [state]
  /// (which stays a bare `Set<int>` for its many consumers); read via
  /// [priceAtFavorite] at render time — the favorites grid rebuilds on every
  /// set change, so reads stay fresh.
  final Map<int, int> _prices;

  static Set<int> _load(SharedPreferences p) {
    final raw = p.getStringList(_kFavKey) ?? [];
    return raw.map(int.parse).toSet();
  }

  static Map<int, int> _loadPrices(SharedPreferences p) {
    final raw = p.getString(_kFavPriceKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in decoded.entries)
          int.parse(e.key): (e.value as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  void _persistPrices() {
    _prefs.setString(
      _kFavPriceKey,
      jsonEncode({for (final e in _prices.entries) '${e.key}': e.value}),
    );
  }

  /// Toggles a favorite. When favoriting and [priceMinor] is supplied, snapshots
  /// the price the user is looking at (FAV-07); when un-favoriting, drops the
  /// snapshot so a later re-favorite captures a fresh baseline.
  void toggle(int productId, {int? priceMinor}) {
    final next = Set<int>.from(state);
    if (next.contains(productId)) {
      next.remove(productId);
      if (_prices.remove(productId) != null) _persistPrices();
    } else {
      next.add(productId);
      if (priceMinor != null) {
        _prices[productId] = priceMinor;
        _persistPrices();
      }
    }
    state = next;
    _prefs.setStringList(_kFavKey, next.map((e) => e.toString()).toList());
  }

  bool isFavorite(int productId) => state.contains(productId);

  /// The price the user saw when they favorited [productId], or `null` if it was
  /// favorited before FAV-07 (no snapshot) or isn't favorited. The favorites
  /// surface compares this against the live price to show the price-drop cue;
  /// no snapshot ⇒ no cue (graceful — never a fabricated baseline).
  int? priceAtFavorite(int productId) => _prices[productId];

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
