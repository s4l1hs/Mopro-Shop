import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/features/account/providers/fit_profile_provider.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_size_recommendation.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AuthedNotifier extends AuthNotifier {
  _AuthedNotifier({required bool authed}) : _authed = authed;
  final bool _authed;
  @override
  Future<AuthState> build() async =>
      _authed ? const AuthAuthenticated() : const AuthUnauthenticated();
}

Future<void> _pump(
  WidgetTester tester, {
  required bool authed,
  SizeRecommendation? rec,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(() => _AuthedNotifier(authed: authed)),
          sizeRecommendationProvider(7).overrideWith((ref) async => rec),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PdpSizeRecommendation(productId: 7)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

SizeRecommendation _rec(String status, {String? size, String? signal}) =>
    SizeRecommendation(
      status: status,
      size: size,
      signal: signal,
      chartApproximate: true,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('guest → renders nothing', (tester) async {
    await _pump(tester, authed: false, rec: _rec('ok', size: 'M'));
    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('fit.your_size'), findsNothing);
  });

  testWidgets('no_chart → renders nothing', (tester) async {
    await _pump(tester, authed: true, rec: _rec('no_chart'));
    expect(find.textContaining('fit.your_size'), findsNothing);
    expect(find.textContaining('fit.cta_complete_profile'), findsNothing);
  });

  testWidgets('ok → shows your-size + the approximate flag', (tester) async {
    await _pump(
      tester,
      authed: true,
      rec: _rec('ok', size: 'M', signal: 'true_to_size'),
    );
    expect(find.textContaining('fit.your_size'), findsOneWidget);
    expect(find.textContaining('fit.approximate'), findsOneWidget);
  });

  testWidgets('no_profile → shows complete-profile CTA', (tester) async {
    await _pump(tester, authed: true, rec: _rec('no_profile'));
    expect(find.textContaining('fit.cta_complete_profile'), findsOneWidget);
    expect(find.textContaining('fit.cta_button'), findsOneWidget);
  });
}
