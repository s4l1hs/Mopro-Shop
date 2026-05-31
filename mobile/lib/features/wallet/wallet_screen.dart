import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/utils/coin_formatter.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/wallet/providers/cashback_plans_provider.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:mopro/features/wallet/widgets/plan_card.dart';
import 'package:mopro/features/wallet/widgets/transaction_tile.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final plans = ref.watch(cashbackPlansProvider);

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('wallet.title'.tr())),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.read(walletProvider.notifier).refresh(),
          ref.read(cashbackPlansProvider.notifier).refresh(),
        ]),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Balance card ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _BalanceCard(state: wallet),
            ),

            // ── Transactions ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'wallet.transactions'.tr(),
              ),
            ),
            ..._transactionSlivers(context, ref, wallet),

            // ── Cashback plans ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'cashback.plans_title'.tr(),
              ),
            ),
            ..._planSlivers(context, ref, plans),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<Widget> _transactionSlivers(
    BuildContext context,
    WidgetRef ref,
    WalletState state,
  ) {
    if (state.transactions.isLoading) {
      return [
        const SliverToBoxAdapter(child: _LoadingSpinner()),
      ];
    }
    if (state.transactions.hasError) {
      final err = state.transactions.error;
      final appError = err is AppError
          ? err
          : UnknownError(
              statusCode: 0,
              message: err.toString(),
            );
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () =>
                  ref.read(walletProvider.notifier).refresh(),
            ),
          ),
        ),
      ];
    }
    final txns = state.transactions.valueOrNull ?? [];
    if (txns.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: _EmptyState(
            icon: Icons.receipt_long_outlined,
            messageKey: 'wallet.no_transactions',
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: txns.length,
        itemBuilder: (_, i) =>
            TransactionTile(transaction: txns[i]),
      ),
      if (state.hasMore)
        SliverToBoxAdapter(
          child: _LoadMoreButton(
            loading: state.loadingMore,
            label: 'wallet.load_more_transactions'.tr(),
            onPressed: () =>
                ref.read(walletProvider.notifier).loadMore(),
          ),
        ),
      if (state.loadMoreError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: state.loadMoreError!,
              onRetry: () =>
                  ref.read(walletProvider.notifier).loadMore(),
            ),
          ),
        ),
    ];
  }

  List<Widget> _planSlivers(
    BuildContext context,
    WidgetRef ref,
    CashbackPlansState state,
  ) {
    if (state.plans.isLoading) {
      return [
        const SliverToBoxAdapter(child: _LoadingSpinner()),
      ];
    }
    if (state.plans.hasError) {
      final err = state.plans.error;
      final appError = err is AppError
          ? err
          : UnknownError(
              statusCode: 0,
              message: err.toString(),
            );
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () =>
                  ref.read(cashbackPlansProvider.notifier).refresh(),
            ),
          ),
        ),
      ];
    }
    final plans = state.plans.valueOrNull ?? [];
    if (plans.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: _EmptyState(
            icon: Icons.card_giftcard_outlined,
            messageKey: 'cashback.no_plans',
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: plans.length,
        itemBuilder: (_, i) => PlanCard(
          plan: plans[i],
          onTap: () => context.push('/wallet/plans/${plans[i].id}'),
        ),
      ),
      if (state.hasMore)
        SliverToBoxAdapter(
          child: _LoadMoreButton(
            loading: state.loadingMore,
            label: 'cashback.load_more_plans'.tr(),
            onPressed: () =>
                ref.read(cashbackPlansProvider.notifier).loadMore(),
          ),
        ),
      if (state.loadMoreError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: state.loadMoreError!,
              onRetry: () =>
                  ref
                      .read(cashbackPlansProvider.notifier)
                      .loadMore(),
            ),
          ),
        ),
    ];
  }
}

// ── Private helpers

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.state});

  final WalletState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.all(16),
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'wallet.coin_balance'.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            state.balance.when(
              loading: () => const SizedBox(
                height: 32,
                width: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, __) => Text(
                '— MC',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              data: (balance) => Text(
                formatCoin(
                  balance.amountMinor,
                  balance.currency,
                  compact: false,
                ),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.messageKey,
  });

  final IconData icon;
  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            messageKey.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _LoadingSpinner extends StatelessWidget {
  const _LoadingSpinner();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.loading,
    required this.label,
    required this.onPressed,
  });

  final bool loading;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: onPressed,
                  child: Text(label),
                ),
        ),
      );
}
