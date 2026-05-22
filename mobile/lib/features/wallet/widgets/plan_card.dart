import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/core/utils/coin_formatter.dart';
import 'package:mopro_api/mopro_api.dart';

/// Card summarising a single cashback plan for the wallet screen list.
class PlanCard extends StatelessWidget {
  const PlanCard({
    required this.plan,
    required this.onTap,
    super.key,
  });

  final CashbackPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _ProductThumbnail(imageUrl: plan.productImageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.productTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatCoin(
                              plan.monthlyAmountMinor,
                              plan.currency,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _PlanStatusBadge(status: plan.status),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl!,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(colorScheme),
        ),
      );
    }
    return _placeholder(colorScheme);
  }

  Widget _placeholder(ColorScheme colorScheme) => Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.shopping_bag_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 24,
        ),
      );
}

class _PlanStatusBadge extends StatelessWidget {
  const _PlanStatusBadge({required this.status});

  final CashbackPlanStatusEnum status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      CashbackPlanStatusEnum.active => (
          'cashback.plan_status_active'.tr(),
          colorScheme.primary,
        ),
      CashbackPlanStatusEnum.cancelled => (
          'cashback.plan_status_cancelled'.tr(),
          colorScheme.error,
        ),
      CashbackPlanStatusEnum.suspended => (
          'cashback.plan_status_suspended'.tr(),
          colorScheme.tertiary,
        ),
    };
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
