import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/account/providers/membership_provider.dart';
import 'package:mopro/features/account/widgets/membership_tier_card.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// AC-05 phase 1: tier badge + progress card states.

Future<void> _pump(WidgetTester tester, Membership? m) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          membershipProvider.overrideWith((ref) async => m),
        ],
        child: const MaterialApp(home: Scaffold(body: MembershipTierCard())),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('mid-ladder: badge + progress bar + next-tier caption',
      (tester) async {
    await _pump(
      tester,
      Membership(
        tier: 'gold',
        rank: 2,
        windowDays: 365,
        spendMinor: 500000,
        orderCount: 7,
        currency: 'TRY',
        nextTier: 'elite',
        nextMinSpendMinor: 1000000,
        nextMinOrders: 15,
      ),
    );
    // i18n bundle isn't loaded in tests → .tr() returns the key.
    expect(find.textContaining('account.tier_current'), findsOneWidget);
    expect(find.textContaining('account.tier_next_progress'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    // binding constraint: min(spend 0.5, orders 7/15≈0.467) = orders ratio.
    expect(bar.value, closeTo(7 / 15, 0.001));
  });

  testWidgets('top tier: no progress bar, top caption', (tester) async {
    await _pump(
      tester,
      Membership(
        tier: 'elite',
        rank: 3,
        windowDays: 365,
        spendMinor: 2500000,
        orderCount: 31,
        currency: 'TRY',
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('account.tier_top'), findsOneWidget);
  });

  testWidgets('no data renders nothing (enrichment, never a blocker)',
      (tester) async {
    await _pump(tester, null);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('account.tier_current'), findsNothing);
  });
}
