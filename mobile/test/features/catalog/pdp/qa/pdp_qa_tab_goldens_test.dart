@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/pdp/qa/pdp_qa_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

/// Serves a fixed Q&A payload (3 questions, total 8 → "Daha fazla" present) or
/// an empty set.
class _GoldenAdapter implements HttpClientAdapter {
  _GoldenAdapter({required this.empty});
  final bool empty;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final items = empty
        ? const <Map<String, dynamic>>[]
        : List.generate(3, (i) {
            return {
              'id': i + 1,
              'product_id': 1,
              'user_id': 100 + i,
              'author_name': 'Kullanıcı ${i + 1}',
              'body': 'Bu ürün hakkında merak ettiğim bir soru ${i + 1}?',
              'answer_count': i,
              'created_at': '2026-0${i + 1}-1${i}T10:00:00Z',
            };
          });
    return ResponseBody.fromString(
      jsonEncode({
        'data': items,
        'total': empty ? 0 : 8,
        'page': 1,
        'hasMore': !empty,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(
  WidgetTester tester, {
  required bool empty,
  required double width,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio()..httpClientAdapter = _GoldenAdapter(empty: empty);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          home: const Scaffold(body: PdpQaTab(productId: 1)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('pdp qa tab populated 375 light', (tester) async {
    await _pump(tester, empty: false, width: 375, brightness: Brightness.light);
    await expectLater(
      find.byType(PdpQaTab),
      matchesGoldenFile('goldens/pdp_qa_tab_populated_375_light.png'),
    );
  });

  testWidgets('pdp qa tab populated 1440 light', (tester) async {
    await _pump(
      tester,
      empty: false,
      width: 1440,
      brightness: Brightness.light,
    );
    await expectLater(
      find.byType(PdpQaTab),
      matchesGoldenFile('goldens/pdp_qa_tab_populated_1440_light.png'),
    );
  });

  testWidgets('pdp qa tab populated 375 dark', (tester) async {
    await _pump(tester, empty: false, width: 375, brightness: Brightness.dark);
    await expectLater(
      find.byType(PdpQaTab),
      matchesGoldenFile('goldens/pdp_qa_tab_populated_375_dark.png'),
    );
  });

  testWidgets('pdp qa tab empty 375 light', (tester) async {
    await _pump(tester, empty: true, width: 375, brightness: Brightness.light);
    await expectLater(
      find.byType(PdpQaTab),
      matchesGoldenFile('goldens/pdp_qa_tab_empty_375_light.png'),
    );
  });
}