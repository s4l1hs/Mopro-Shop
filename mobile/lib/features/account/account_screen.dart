import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/wallet/providers/cashback_plans_provider.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:mopro/utils/money.dart';
import 'package:mopro_api/mopro_api.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ordersState = ref.watch(ordersProvider);
    final walletState = ref.watch(walletProvider);
    final plansState = ref.watch(cashbackPlansProvider);

    final activeOrderCount = ordersState.orders.valueOrNull
            ?.where(
              (o) =>
                  o.status != 'delivered' &&
                  o.status != 'cancelled' &&
                  o.status != 'refunded',
            )
            .length ??
        0;

    final balanceMinor =
        walletState.balance.valueOrNull?.amountMinor ?? 0;

    final activePlanCount =
        plansState.plans.valueOrNull
            ?.where((p) => p.status == CashbackPlanStatusEnum.active)
            .length ??
            0;

    return Scaffold(
      appBar: AppBar(title: Text('nav.account'.tr())),
      body: ListView(
        children: [
          // ── Avatar header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    'M',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Mopro Kullanıcısı',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          // ── Summary stats ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.15,
              children: [
                _StatCard(
                  label: 'account.active_orders'.tr(),
                  value: '$activeOrderCount',
                  icon: Icons.shopping_bag_outlined,
                  cs: cs,
                  theme: theme,
                  onTap: () => context.push('/orders'),
                ),
                _StatCard(
                  label: 'account.coin_balance'.tr(),
                  value: MoneyUtils.formatMinor(balanceMinor, currency: 'TRY_COIN'),
                  icon: Icons.account_balance_wallet_outlined,
                  cs: cs,
                  theme: theme,
                  onTap: () => context.push('/wallet'),
                ),
                _StatCard(
                  label: 'account.active_plans'.tr(),
                  value: '$activePlanCount',
                  icon: Icons.card_giftcard_outlined,
                  cs: cs,
                  theme: theme,
                  onTap: () => context.push('/wallet'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          _Section(
            title: 'account.orders_section'.tr(),
            items: [
              _NavItem(
                icon: Icons.shopping_bag_outlined,
                label: 'account.my_orders'.tr(),
                onTap: () => context.push('/orders'),
              ),
              _NavItem(
                icon: Icons.account_balance_wallet_outlined,
                label: 'account.cashback_wallet'.tr(),
                onTap: () => context.push('/wallet'),
              ),
            ],
          ),
          _Section(
            title: 'account.settings_section'.tr(),
            items: [
              _NavItem(
                icon: Icons.person_outline,
                label: 'account.profile'.tr(),
                onTap: () => context.push('/account/profile'),
              ),
              _NavItem(
                icon: Icons.location_on_outlined,
                label: 'address.list_title'.tr(),
                onTap: () => context.push('/profile/addresses'),
              ),
              _NavItem(
                icon: Icons.credit_card_outlined,
                label: 'account.saved_cards'.tr(),
                onTap: () => context.push('/account/cards'),
              ),
              _NavItem(
                icon: Icons.security_outlined,
                label: 'account.security'.tr(),
                onTap: () => context.push('/account/security'),
              ),
            ],
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text('account.logout'.tr()),
            onTap: () => ref.read(authNotifierProvider.notifier).setLoggedOut(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.cs,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final ColorScheme cs;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: cs.primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});
  final String title;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
          ),
        ),
        ...items,
        const Divider(height: 1),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
