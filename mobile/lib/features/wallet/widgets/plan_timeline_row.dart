import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/core/utils/coin_formatter.dart';
import 'package:mopro/features/wallet/widgets/month_dot.dart';
import 'package:mopro_api/mopro_api.dart';

/// One row in the cashback payment timeline.
class PlanTimelineRow extends StatelessWidget {
  const PlanTimelineRow({
    required this.payment,
    required this.currency,
    super.key,
  });

  final CashbackPayment payment;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      child: Row(
        children: [
          MonthDot(status: payment.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatPeriodLabel(payment.periodYyyymm),
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  formatCoin(payment.amountMinor, currency),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(status: payment.status),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CashbackPaymentStatusEnum status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (status) {
      CashbackPaymentStatusEnum.paid => (
          'cashback.payment_status_paid'.tr(),
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
        ),
      CashbackPaymentStatusEnum.scheduled => (
          'cashback.payment_status_scheduled'.tr(),
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurfaceVariant,
        ),
      CashbackPaymentStatusEnum.failed => (
          'cashback.payment_status_failed'.tr(),
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg),
      ),
    );
  }
}
