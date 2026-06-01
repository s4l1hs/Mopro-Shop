import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/seller/providers/seller_dashboard_provider.dart';
import 'package:mopro/features/seller/user_is_seller_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// `/seller/dashboard` — seller panel landing. Overview counters + quick links.
class SellerDashboardScreen extends ConsumerWidget {
  const SellerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final binding = ref.watch(currentSellerBindingProvider);
    final summaryAsync = ref.watch(sellerDashboardSummaryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('seller.panel_title'.tr()),
        actions: [
          IconButton(
            tooltip: 'seller.load_more'.tr(),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(sellerDashboardSummaryProvider),
          ),
        ],
      ),
      body: CenteredContentColumn(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header: seller name + role chip.
            Row(
              children: [
                Expanded(
                  child: Text(
                    binding?.sellerName ?? 'seller.panel_title'.tr(),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (binding != null) _RoleChip(role: binding.role),
              ],
            ),
            const SizedBox(height: 16),
            summaryAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('seller.error_generic'.tr()),
              ),
              data: (s) => s.allClear
                  ? const _AllDone()
                  : _Cards(summary: s),
            ),
            const SizedBox(height: 24),
            _QuickActions(slug: binding?.sellerSlug),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final SellerBindingRoleEnum role;

  @override
  Widget build(BuildContext context) {
    final label = role == SellerBindingRoleEnum.owner
        ? 'seller.role_owner'.tr()
        : 'seller.role_staff'.tr();
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards({required this.summary});
  final SellerDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _OverviewCard(
        label: 'seller.card_pending_returns'.tr(),
        value: summary.pendingReturnsHasMore
            ? '${summary.pendingReturns}+'
            : '${summary.pendingReturns}',
        icon: Icons.assignment_return_outlined,
        onTap: () => context.go('/seller/returns?status=submitted'),
      ),
      _OverviewCard(
        label: 'seller.card_unanswered_questions'.tr(),
        value: '${summary.unansweredQuestions}',
        icon: Icons.help_outline_rounded,
        onTap: () => context.go('/seller/questions?unanswered=true'),
      ),
    ];
    if (context.isMobile) {
      return Column(
        children: [
          for (final c in cards)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
        ],
      );
    }
    return Row(
      children: [
        for (final c in cards)
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: c)),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 28, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.slug});
  final String? slug;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => context.go('/seller/returns'),
          icon: const Icon(Icons.assignment_return_outlined, size: 18),
          label: Text('seller.go_to_returns'.tr()),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/seller/questions'),
          icon: const Icon(Icons.help_outline_rounded, size: 18),
          label: Text('seller.answer_questions'.tr()),
        ),
        if (slug != null && slug!.isNotEmpty)
          TextButton.icon(
            onPressed: () => context.push('/sellers/$slug'),
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: Text('seller.view_storefront'.tr()),
          ),
      ],
    );
  }
}

class _AllDone extends StatelessWidget {
  const _AllDone();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'seller.all_done_title'.tr(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'seller.all_done_body'.tr(),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
