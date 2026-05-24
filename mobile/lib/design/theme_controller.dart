import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'mopro_theme_mode';

/// Cycles through system → light → dark and persists the choice.
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(SharedPreferences prefs)
      : _prefs = prefs,
        super(_load(prefs));

  final SharedPreferences _prefs;

  static ThemeMode _load(SharedPreferences p) {
    return switch (p.getString(_kThemeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void cycle() {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    _apply(next);
  }

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
