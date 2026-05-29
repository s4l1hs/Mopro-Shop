import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'mopro_theme_mode';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> seed) async {
    SharedPreferences.setMockInitialValues(seed);
    return SharedPreferences.getInstance();
  }

  test('fresh install defaults to light and persists light', () async {
    final prefs = await prefsWith({});
    final c = ThemeController(prefs);
    expect(c.state, ThemeMode.light);
    expect(prefs.getString(_key), 'light');
  });

  test('legacy "system" migrates to light and is rewritten once', () async {
    final prefs = await prefsWith({_key: 'system'});
    final c = ThemeController(prefs);
    expect(c.state, ThemeMode.light);
    expect(prefs.getString(_key), 'light');
  });

  test('stored "dark" is preserved unchanged', () async {
    final prefs = await prefsWith({_key: 'dark'});
    final c = ThemeController(prefs);
    expect(c.state, ThemeMode.dark);
    expect(prefs.getString(_key), 'dark');
  });

  test('unknown stored value falls back to light', () async {
    final prefs = await prefsWith({_key: 'sepia'});
    final c = ThemeController(prefs);
    expect(c.state, ThemeMode.light);
    expect(prefs.getString(_key), 'light');
  });

  test('cycle toggles light <-> dark only (never system)', () async {
    final prefs = await prefsWith({});
    final c = ThemeController(prefs);
    expect(c.state, ThemeMode.light);
    c.cycle();
    expect(c.state, ThemeMode.dark);
    expect(prefs.getString(_key), 'dark');
    c.cycle();
    expect(c.state, ThemeMode.light);
    expect(prefs.getString(_key), 'light');
  });

  test('setMode persists the chosen mode', () async {
    final prefs = await prefsWith({});
    final c = ThemeController(prefs)..setMode(ThemeMode.dark);
    expect(c.state, ThemeMode.dark);
    expect(prefs.getString(_key), 'dark');
  });
}
