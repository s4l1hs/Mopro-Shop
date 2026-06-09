import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/utils/coin_formatter.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/core/widgets/loading_spinner.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:mopro/features/wallet/widgets/transaction_tile.dart';
import 'package:mopro_api/mopro_api.dart';

/// Coin hub (IA-02) — the screen behind the Coin tab (IA-01).
///
/// Read-only hub on Mopro's real coin ledger: balance, earn/spend history, and
/// ways-to-earn. Reuses [walletProvider] (GET /wallet/balance + /wallet/
/// transactions) and the shared [TransactionTile] — no fabricated values.
/// Redeem is DEFER'd (no discrete idempotent ledger-correct redeem endpoint;
/// coin-spend today is the checkout `coin_balance` payment method, out of scope)
/// — surfaced as a "coming soon" card. Coins are per-user, so the hub is soft
/// guest-gated. Full cashback plans live on the existing `/wallet` screen.
class CoinHubScreen extends ConsumerWidget {
  const CoinHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authNotifierProvider).valueOrNull is AuthAuthenticated;

    // Suppress the screen's own AppBar when a responsive shell already supplies
    // top chrome: the AccountShell two-pane (scope) OR the desktop/tablet
    // `_WebShell` (WebHeader + MegaMenuBar, mounted whenever we're not mobile).
    // On mobile (`_MobileShell` — bottom nav, no top bar) the AppBar stays.
    final suppressBar =
        AccountChromeScope.suppressed(context) || !context.isMobile;

    return Scaffold(
      appBar: suppressBar ? null : AppBar(title: Text('coin.hub_title'.tr())),
      body: authed ? _Hub() : const _GuestGate(),
    );
  }
}

class _Hub extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    // Mobile: full-width (unchanged). Tablet/desktop: clamp + center each
    // section so the hub reads like a premier sub-domain, not a full-bleed log
    // — same pattern as the Home screen's `wrap()`.
    final isMobile = context.isMobile;
    Widget wrap(Widget child) =>
        isMobile ? child : CenteredContentColumn(child: child);

    return RefreshIndicator(
      onRefresh: () => ref.read(walletProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: wrap(_BalanceHeader(balance: wallet.balance)),
          ),
          SliverToBoxAdapter(child: wrap(const _WaysToEarnSection())),
          SliverToBoxAdapter(child: wrap(const _RedeemSection())),
          SliverToBoxAdapter(
            child: wrap(_SectionHeader(title: 'coin.recent_activity'.tr())),
          ),
          ..._activitySlivers(context, ref, wallet, wrap),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _activitySlivers(
    BuildContext context,
    WidgetRef ref,
    WalletState state,
    Widget Function(Widget) wrap,
  ) {
    if (state.transactions.isLoading) {
      return [SliverToBoxAdapter(child: wrap(const LoadingSpinner()))];
    }
    if (state.transactions.hasError) {
      final err = state.transactions.error;
      final appError = err is AppError
          ? err
          : UnknownError(statusCode: 0, message: err.toString());
      return [
        SliverToBoxAdapter(
          child: wrap(
            Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorBanner(
                error: appError,
                onRetry: () => ref.read(walletProvider.notifier).refresh(),
              ),
            ),
          ),
        ),
      ];
    }
    final txns = state.transactions.valueOrNull ?? [];
    if (txns.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: wrap(
            const _EmptyState(
              icon: Icons.receipt_long_outlined,
              messageKey: 'wallet.no_transactions',
            ),
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: txns.length,
        itemBuilder: (_, i) => wrap(TransactionTile(transaction: txns[i])),
      ),
      // Full history + cashback plans live on the existing wallet screen.
      SliverToBoxAdapter(
        child: wrap(
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: OutlinedButton(
                onPressed: () => context.push('/wallet'),
                child: Text('coin.see_all'.tr()),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.balance});

  final AsyncValue<WalletBalance> balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.all(16),
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.monetization_on,
                  color: cs.onPrimaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  'wallet.coin_balance'.tr(),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: cs.onPrimaryContainer),
                ),
              ],
            ),
            const SizedBox(height: 8),
            balance.when(
              loading: () => const SizedBox(
                height: 32,
                width: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, __) => Text(
                '— MC',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: cs.onPrimaryContainer),
              ),
              data: (b) => Text(
                formatCoin(b.amountMinor, b.currency, compact: false),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: cs.onPrimaryContainer,
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

class _WaysToEarnSection extends StatelessWidget {
  const _WaysToEarnSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'coin.ways_to_earn_title'.tr()),
        const _EarnTile(
          icon: Icons.shopping_bag_outlined,
          titleKey: 'coin.earn_shop_title',
          bodyKey: 'coin.earn_shop_body',
        ),
        const _EarnTile(
          icon: Icons.autorenew,
          titleKey: 'coin.earn_perpetual_title',
          bodyKey: 'coin.earn_perpetual_body',
        ),
      ],
    );
  }
}

class _EarnTile extends StatelessWidget {
  const _EarnTile({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
      ),
      title: Text(titleKey.tr()),
      subtitle: Text(bodyKey.tr()),
    );
  }
}

class _RedeemSection extends StatelessWidget {
  const _RedeemSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        color: cs.surfaceContainerHighest,
        child: ListTile(
          leading: Icon(Icons.redeem_outlined, color: cs.onSurfaceVariant),
          title: Text('coin.redeem_title'.tr()),
          subtitle: Text('coin.redeem_coming_soon'.tr()),
          trailing: Chip(
            label: Text('coin.coming_soon'.tr()),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}

class _GuestGate extends StatelessWidget {
  const _GuestGate();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monetization_on_outlined, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'coin.login_required_title'.tr(),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'coin.login_required_body'.tr(),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.push('/auth/login'),
              child: Text('coin.login_cta'.tr()),
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
  const _EmptyState({required this.icon, required this.messageKey});

  final IconData icon;
  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(
            messageKey.tr(),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
