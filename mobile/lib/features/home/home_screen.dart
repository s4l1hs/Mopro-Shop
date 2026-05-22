import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/home/providers/home_wallet_summary_provider.dart';
import 'package:mopro/features/wallet/widgets/coin_balance_pill.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(homeWalletSummaryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: summaryAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (balance) => CoinBalancePill(
                  amountMinor: balance.amountMinor,
                  currency: balance.currency,
                  onTap: () => context.push('/wallet'),
                ),
              ),
            ),
            const Expanded(
              child: Center(child: Text('Mopro Home')),
            ),
          ],
        ),
      ),
    );
  }
}
