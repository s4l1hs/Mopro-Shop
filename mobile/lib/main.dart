import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mopro/app.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Injected at build time via --dart-define-from-file=dart_defines/dev.json
const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.moproshop.com',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await Future.wait([
    initializeDateFormatting('tr_TR'),
    initializeDateFormatting('en_US'),
  ]);

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
        Locale('de', 'DE'),
        Locale('ar', 'AE'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          apiBaseUrlProvider.overrideWithValue(_apiBaseUrl),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MoproApp(),
      ),
    ),
  );
}
