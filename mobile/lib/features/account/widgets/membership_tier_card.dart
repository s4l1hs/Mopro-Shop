import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/account/providers/membership_provider.dart';
import 'package:mopro/utils/money.dart';

/// AC-05 phase 1: membership-tier badge + progress-to-next card on the Account
/// surface. Pure display of the derived read-model — no benefit enforcement
/// (later phases). Loading/error render nothing: the card is enrichment, never
/// a blocker for the Account screen.
class MembershipTierCard extends ConsumerWidget {
  const MembershipTierCard({super.key});

  /// Tier codes are reference data; the client maps known codes to localized
  /// names and falls back to the raw code for codes it doesn't know yet.
  static String tierLabel(String code) {
    const known = {'classic', 'gold', 'elite'};
    return known.contains(code) ? 'account.tier_$code'.tr() : code;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(membershipProvider);
    final m = state.valueOrNull;
    if (m == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasNext = m.nextTier != null &&
        m.nextMinSpendMinor != null &&
        m.nextMinOrders != null;

    // Both thresholds must be met → progress is the binding constraint.
    double progress = 1;
    if (hasNext) {
      final spendRatio = m.nextMinSpendMinor! == 0
          ? 1.0
          : m.spendMinor / m.nextMinSpendMinor!;
      final orderRatio =
          m.nextMinOrders! == 0 ? 1.0 : m.orderCount / m.nextMinOrders!;
      progress = (spendRatio < orderRatio ? spendRatio : orderRatio)
          .clamp(0.0, 1.0);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                size: 20,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'account.tier_current'
                      .tr(namedArgs: {'tier': tierLabel(m.tier)}),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (hasNext) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'account.tier_next_progress'.tr(namedArgs: {
                'tier': tierLabel(m.nextTier!),
                'spend': MoneyUtils.formatMinor(m.spendMinor),
                'targetSpend': MoneyUtils.formatMinor(m.nextMinSpendMinor!),
                'orders': '${m.orderCount}',
                'targetOrders': '${m.nextMinOrders}',
              },),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'account.tier_top'.tr(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          // Membership benefits (migration 0106). Non-financial surfacing of what
          // the tier unlocks. Today's shipped benefit is tier-exclusive coupons,
          // available above the base (classic, rank 1) tier; the actual eligibility
          // is enforced server-side at coupon apply (display==charge).
          if (m.rank > 1) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.local_activity_outlined,
                  size: 16,
                  color: cs.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'membership.benefit_exclusive_coupons'.tr(),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
