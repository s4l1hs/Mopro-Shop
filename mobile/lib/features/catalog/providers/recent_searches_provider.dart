import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

final recentSearchesProvider =
    StateNotifierProvider<RecentSearchesNotifier, List<String>>(
  (ref) => RecentSearchesNotifier(ref.watch(sharedPreferencesProvider)),
);

class RecentSearchesNotifier extends StateNotifier<List<String>> {
  RecentSearchesNotifier(this._prefs) : super([]) {
    _load();
  }

  static const _key = 'mopro_recent_searches';
  static const _max = 5;

  final SharedPreferences _prefs;

  void _load() {
    state = _prefs.getStringList(_key) ?? [];
  }

  void add(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final updated =
        [q, ...state.where((s) => s != q)].take(_max).toList();
    state = updated;
    _prefs.setStringList(_key, updated);
  }

  void remove(String query) {
    state = state.where((s) => s != query).toList();
    _prefs.setStringList(_key, state);
  }

  void clear() {
    state = [];
    _prefs.remove(_key);
  }
}
