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
import 'package:mopro/features/account/questions/my_questions_screen.dart';
import 'package:mopro/features/account/reviews/my_reviews_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

/// Serves both /me/reviews and /me/questions; [empty] toggles an empty payload.
class _GoldenAdapter implements HttpClientAdapter {
  _GoldenAdapter({required this.empty});
  final bool empty;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isReviews = options.path.contains('/reviews');
    final data = empty
        ? const <Map<String, dynamic>>[]
        : isReviews
            ? List.generate(3, (i) {
                return {
                  'id': i + 1,
                  'product_id': 10 + i,
                  'user_id': 100,
                  'rating': 5 - i,
                  'title': 'Memnun kaldım ${i + 1}',
                  'body': 'Ürün açıklamadaki gibi geldi, teşekkürler.',
                  'status': 'published',
                  'created_at': '2026-0${i + 1}-10T10:00:00Z',
                  'updated_at': '2026-0${i + 1}-10T10:00:00Z',
                  'product_title': 'Örnek Ürün ${i + 1}',
                  'product_slug': 'ornek-urun-${i + 1}',
                  'product_thumbnail': '',
                };
              })
            : List.generate(3, (i) {
                return {
                  'id': i + 1,
                  'product_id': 10 + i,
                  'user_id': 100,
                  'author_name': 'Ben',
                  'body': 'Sorduğum soru ${i + 1}: stok ne zaman gelir?',
                  'answer_count': i,
                  'created_at': '2026-0${i + 1}-10T10:00:00Z',
                };
              });
    return ResponseBody.fromString(
      jsonEncode({
        'data': data,
        'total': empty ? 0 : 3,
        'page': 1,
        'hasMore': false,
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
  WidgetTester tester,
  Widget screen, {
  required bool empty,
  required double width,
}) async {
  tester.view.physicalSize = Size(width, 1000);
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
          theme: buildLightTheme(),
          home: screen,
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

  testWidgets('my reviews populated 1440 light', (tester) async {
    await _pump(
      tester,
      const MyReviewsScreen(),
      empty: false,
      width: 1440,
    );
    await expectLater(
      find.byType(MyReviewsScreen),
      matchesGoldenFile('goldens/my_reviews_populated_1440_light.png'),
    );
  });

  testWidgets('my reviews empty 375 light', (tester) async {
    await _pump(tester, const MyReviewsScreen(), empty: true, width: 375);
    await expectLater(
      find.byType(MyReviewsScreen),
      matchesGoldenFile('goldens/my_reviews_empty_375_light.png'),
    );
  });

  testWidgets('my questions populated 1440 light', (tester) async {
    await _pump(
      tester,
      const MyQuestionsScreen(),
      empty: false,
      width: 1440,
    );
    await expectLater(
      find.byType(MyQuestionsScreen),
      matchesGoldenFile('goldens/my_questions_populated_1440_light.png'),
    );
  });
}
