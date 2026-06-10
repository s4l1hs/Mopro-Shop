@Tags(['golden'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';
import 'package:mopro/features/seller/providers/seller_dashboard_provider.dart';
import 'package:mopro/features/seller/screens/seller_dashboard_screen.dart';
import 'package:mopro/features/seller/screens/seller_questions_inbox_screen.dart';
import 'package:mopro/features/seller/screens/seller_return_detail_screen.dart';
import 'package:mopro/features/seller/screens/seller_returns_inbox_screen.dart';
import 'package:mopro/features/seller/user_is_seller_provider.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

SellerBinding _binding() => SellerBinding(
      sellerId: 1,
      sellerSlug: 'acme-store',
      sellerName: 'Acme Store',
      role: SellerBindingRoleEnum.owner,
    );

SellerReturn _ret(int id, {String status = 'submitted'}) => SellerReturn(
      id: id,
      orderId: 5000 + id,
      status: status,
      reason: 'damaged',
      description: 'Kutu ezilmiş geldi.',
      refundAmountMinor: 12900,
      refundCurrency: 'TRY',
      createdAt: DateTime.utc(2026, 5, 2),
    );

SellerQuestion _q(int id) => SellerQuestion(
      id: id,
      productId: 100 + id,
      userId: 7000 + id,
      body: 'Bu ürün su geçirmez mi? Detaylı bilgi alabilir miyim? #$id',
      answerCount: 0,
      createdAt: DateTime.utc(2026, 5, 2),
    );

class _Repo extends SellerRepository {
  _Repo({this.returns = const [], this.questions = const []}) : super(Dio());
  final List<SellerReturn> returns;
  final List<SellerQuestion> questions;
  @override
  Future<(List<SellerReturn>, bool)> listReturns({
    required String status,
    int limit = 20,
    int offset = 0,
  }) async =>
      (returns, false);
  @override
  Future<(List<SellerQuestion>, int, bool)> listQuestions({
    required bool unanswered,
    int page = 1,
    int pageSize = 20,
  }) async =>
      (questions, questions.length, false);
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(theme: buildLightTheme(), home: screen),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
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

  testWidgets('seller dashboard populated 1440 light', (tester) async {
    await _pump(
      tester,
      const SellerDashboardScreen(),
      overrides: [
        currentSellerBindingProvider.overrideWithValue(_binding()),
        sellerDashboardSummaryProvider.overrideWith(
          (ref) async => const SellerDashboardSummary(
            pendingReturns: 3,
            pendingReturnsHasMore: false,
            unansweredQuestions: 5,
          ),
        ),
      ],
    );
    await expectLater(
      find.byType(SellerDashboardScreen),
      matchesGoldenFile('goldens/seller_dashboard_populated_1440_light.png'),
    );
  });

  testWidgets('seller dashboard empty 1440 light', (tester) async {
    await _pump(
      tester,
      const SellerDashboardScreen(),
      overrides: [
        currentSellerBindingProvider.overrideWithValue(_binding()),
        sellerDashboardSummaryProvider.overrideWith(
          (ref) async => const SellerDashboardSummary(
            pendingReturns: 0,
            pendingReturnsHasMore: false,
            unansweredQuestions: 0,
          ),
        ),
      ],
    );
    await expectLater(
      find.byType(SellerDashboardScreen),
      matchesGoldenFile('goldens/seller_dashboard_empty_1440_light.png'),
    );
  });

  testWidgets('seller returns inbox 1440 light', (tester) async {
    await _pump(
      tester,
      const SellerReturnsInboxScreen(),
      overrides: [
        sellerRepositoryProvider
            .overrideWithValue(_Repo(returns: [_ret(1), _ret(2)])),
      ],
    );
    await expectLater(
      find.byType(SellerReturnsInboxScreen),
      matchesGoldenFile('goldens/seller_returns_inbox_1440_light.png'),
    );
  });

  testWidgets('seller return detail with actions 1440 light', (tester) async {
    await _pump(
      tester,
      SellerReturnDetailScreen(returnId: 1, initial: _ret(1)),
      overrides: [sellerRepositoryProvider.overrideWithValue(_Repo())],
    );
    await expectLater(
      find.byType(SellerReturnDetailScreen),
      matchesGoldenFile('goldens/seller_return_detail_actions_1440_light.png'),
    );
  });

  testWidgets('seller questions inbox unanswered 1440 light', (tester) async {
    await _pump(
      tester,
      const SellerQuestionsInboxScreen(),
      overrides: [
        sellerRepositoryProvider
            .overrideWithValue(_Repo(questions: [_q(1), _q(2)])),
      ],
    );
    await expectLater(
      find.byType(SellerQuestionsInboxScreen),
      matchesGoldenFile('goldens/seller_questions_inbox_1440_light.png'),
    );
  });
}