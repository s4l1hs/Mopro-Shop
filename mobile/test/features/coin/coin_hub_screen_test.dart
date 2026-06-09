import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/responsive/centered_content_column.dart';
import 'package:mopro/features/coin/coin_hub_screen.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:mopro/features/wallet/widgets/transaction_tile.dart';
import 'package:mopro_api/mopro_api.dart';

import '../../_support/test_harness.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

class _FakeWallet extends WalletNotifier {
  _FakeWallet(this._state);
  final WalletState _state;
  @override
  WalletState build() => _state;
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('guest → login gate (no balance/transactions)', (tester) async {
    await pumpTrendyolApp(
      tester,
      const CoinHubScreen(),
      overrides: [
        authNotifierProvider
            .overrideWith(() => _FakeAuth(const AuthUnauthenticated())),
      ],
    );
    await tester.pump();

    // Gate icon + login CTA; no hub content.
    expect(find.byIcon(Icons.monetization_on_outlined), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(TransactionTile), findsNothing);
  });

  testWidgets('authed → balance + ways-to-earn + redeem + transactions',
      (tester) async {
    final state = WalletState(
      balance: AsyncData(
        WalletBalance(
          currency: 'TRY_COIN',
          amountMinor: 43059,
          lastUpdatedAt: DateTime(2026, 6),
        ),
      ),
      transactions: AsyncData([
        WalletTransaction(
          id: 1,
          type: WalletTransactionTypeEnum.credit,
          amountMinor: 15800,
          currency: 'TRY_COIN',
          occurredAt: DateTime(2026, 5),
        ),
        WalletTransaction(
          id: 2,
          type: WalletTransactionTypeEnum.debit,
          amountMinor: 7499,
          currency: 'TRY_COIN',
          occurredAt: DateTime(2026, 6),
        ),
      ]),
    );

    await pumpTrendyolApp(
      tester,
      const CoinHubScreen(),
      overrides: [
        authNotifierProvider
            .overrideWith(() => _FakeAuth(const AuthAuthenticated())),
        walletProvider.overrideWith(() => _FakeWallet(state)),
      ],
    );
    await tester.pump();

    // Balance header (filled coin icon), ways-to-earn tiles, redeem card,
    // and the seeded transactions rendered via the shared TransactionTile.
    expect(find.byIcon(Icons.monetization_on), findsOneWidget);
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.autorenew), findsOneWidget);
    expect(find.byIcon(Icons.redeem_outlined), findsOneWidget);
    expect(find.byType(TransactionTile), findsNWidgets(2));
    // No guest CTA when authed.
    expect(find.byType(FilledButton), findsNothing);
  });

  // G-1: the hub is responsive. On a wide (web) surface the raw AppBar is
  // suppressed (the `_WebShell` WebHeader supplies top chrome) and the body is
  // clamped via CenteredContentColumn; on a narrow (mobile) surface the AppBar
  // stays and the body is full-width.
  group('responsive shell parity (G-1)', () {
    WalletState authedState() => WalletState(
          balance: AsyncData(
            WalletBalance(
              currency: 'TRY_COIN',
              amountMinor: 43059,
              lastUpdatedAt: DateTime(2026, 6),
            ),
          ),
          transactions: const AsyncData([]),
        );

    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpTrendyolApp(
        tester,
        const CoinHubScreen(),
        overrides: [
          authNotifierProvider
              .overrideWith(() => _FakeAuth(const AuthAuthenticated())),
          walletProvider.overrideWith(() => _FakeWallet(authedState())),
        ],
      );
      await tester.pump();
    }

    testWidgets('wide → AppBar suppressed + body clamped', (tester) async {
      await pumpAt(tester, const Size(1200, 900));
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(CenteredContentColumn), findsWidgets);
    });

    testWidgets('narrow → AppBar shown + full-width body', (tester) async {
      await pumpAt(tester, const Size(390, 900));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(CenteredContentColumn), findsNothing);
    });
  });
}
