import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/order_status_chip.dart';
import 'package:mopro/features/wallet/providers/cashback_plans_provider.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:mopro/utils/money.dart';
import 'package:mopro_api/mopro_api.dart';

/// The default right-pane content at `/account` on desktop/tablet. Authed users
/// see a greeting + three quick-action cards (last order / wallet balance /
/// active campaigns) sourced from existing providers; guests see a value-prop
/// panel with login/register CTAs.
class AccountWelcomePanel extends ConsumerWidget {
  const AccountWelcomePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: user != null ? _Authed(user: user) : const _Guest(),
    );
  }
}

class _Authed extends ConsumerWidget {
  const _Authed({required this.user});
  final CurrentUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = user.displayName.trim().split(RegExp(r'\s+')).first;
    final orders = ref.watch(ordersProvider).orders.valueOrNull ?? const [];
    final balanceMinor =
        ref.watch(walletProvider).balance.valueOrNull?.amountMinor ?? 0;
    final activeCampaigns = (ref.watch(cashbackPlansProvider).plans.valueOrNull ??
            const [])
        .where((p) => p.status == CashbackPlanStatusEnum.active)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'welcome.greeting'.tr(namedArgs: {'name': firstName}),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _LastOrderCard(orders: orders)),
            const SizedBox(width: 12),
            Expanded(child: _WalletCard(balanceMinor: balanceMinor)),
            const SizedBox(width: 12),
            Expanded(child: _CampaignsCard(count: activeCampaigns)),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _LastOrderCard extends StatelessWidget {
  const _LastOrderCard({required this.orders});
  final List<OrderDto> orders;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (orders.isEmpty) {
      return _Card(
        title: 'welcome.card_last_order'.tr(),
        children: [
          Text(
            'welcome.no_orders'.tr(),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _CardCta(
            label: 'welcome.start_shopping'.tr(),
            onTap: () => context.go('/'),
          ),
        ],
      );
    }
    final order = orders.first;
    return _Card(
      title: 'welcome.card_last_order'.tr(),
      children: [
        Text(
          order.createdAt.toIso8601String().split('T').first,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 6),
        OrderStatusChip(status: order.status),
        const SizedBox(height: 12),
        _CardCta(
          label: 'welcome.detail'.tr(),
          onTap: () => context.go('/orders/${order.id}'),
        ),
      ],
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.balanceMinor});
  final int balanceMinor;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'welcome.card_wallet'.tr(),
      children: [
        Text(
          MoneyUtils.formatMinor(balanceMinor, currency: 'TRY_COIN'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _CardCta(
          label: 'welcome.wallet_cta'.tr(),
          onTap: () => context.go('/wallet'),
        ),
      ],
    );
  }
}

class _CampaignsCard extends StatelessWidget {
  const _CampaignsCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'welcome.card_campaigns'.tr(),
      children: [
        Text(
          'welcome.active_count'.tr(namedArgs: {'count': '$count'}),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _CardCta(
          label: 'welcome.campaigns_cta'.tr(),
          onTap: () => context.go('/wallet'),
        ),
      ],
    );
  }
}

class _CardCta extends StatelessWidget {
  const _CardCta({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ── Guest variant ────────────────────────────────────────────────────────────

class _Guest extends StatelessWidget {
  const _Guest();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'welcome.guest_title'.tr(),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'welcome.guest_subtitle'.tr(),
          style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        _reason(
          context,
          Icons.recommend_outlined,
          'welcome.reason_reco_title'.tr(),
          'welcome.reason_reco_desc'.tr(),
        ),
        _reason(
          context,
          Icons.favorite_border_rounded,
          'welcome.reason_fav_title'.tr(),
          'welcome.reason_fav_desc'.tr(),
        ),
        _reason(
          context,
          Icons.local_shipping_outlined,
          'welcome.reason_orders_title'.tr(),
          'welcome.reason_orders_desc'.tr(),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => context.go('/auth/login'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                  ),
                  child: Text('auth.login'.tr()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () => context.go('/auth/register'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.primary,
                    side: BorderSide(color: cs.primary),
                  ),
                  child: Text('account.menu_register'.tr()),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _reason(
    BuildContext context,
    IconData icon,
    String title,
    String desc,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
