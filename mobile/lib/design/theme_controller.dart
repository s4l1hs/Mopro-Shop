import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'mopro_theme_mode';

/// Owns the app theme mode. New installs boot **light**; the app never follows
/// the OS brightness (no `ThemeMode.system`). Users toggle light ↔ dark and the
/// choice persists in [SharedPreferences].
///
/// Migration: any stored value that isn't `'light'`/`'dark'` (legacy `'system'`,
/// absent, or unknown) resolves to light and is rewritten once at init, so the
/// persisted value is always a concrete mode from then on.
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(SharedPreferences prefs)
      : _prefs = prefs,
        super(_initialMode(prefs)) {
    _migrateLegacyValue();
  }

  final SharedPreferences _prefs;

  static ThemeMode _initialMode(SharedPreferences p) {
    return switch (p.getString(_kThemeKey)) {
      'dark' => ThemeMode.dark,
      // 'light', legacy 'system', null, or anything unknown → light default.
      _ => ThemeMode.light,
    };
  }

  void _migrateLegacyValue() {
    final stored = _prefs.getString(_kThemeKey);
    if (stored != 'light' && stored != 'dark') {
      // Rewrite legacy 'system'/null/unknown to the resolved concrete mode.
      _prefs.setString(_kThemeKey, state.name);
    }
  }

  /// Toggles light ↔ dark (no system mode).
  void cycle() =>
      _apply(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  void setMode(ThemeMode mode) => _apply(mode);

  void _apply(ThemeMode mode) {
    state = mode;
    _prefs.setString(_kThemeKey, mode.name);
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('override sharedPreferencesProvider in main'),
);

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((ref) {
  return ThemeController(ref.watch(sharedPreferencesProvider));
});
