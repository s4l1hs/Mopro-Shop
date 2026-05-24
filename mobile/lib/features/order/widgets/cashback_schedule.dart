import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/utils/money.dart';

/// Displays the perpetual cashback payment schedule for an order.
/// Shows the next 3 upcoming payments and a "Plan süresiz devam eder" note.
class CashbackSchedule extends StatelessWidget {
  const CashbackSchedule({
    required this.monthlyMinor,
    required this.currency,
    required this.startDate,
    super.key,
  });

  final int monthlyMinor;
  final String currency;
  final DateTime startDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final now = DateTime.now();
    // First payment month: startDate or the next upcoming month
    final firstPayment = startDate.isAfter(now) ? startDate : now;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.card_giftcard_outlined,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'cashback.schedule_title'.tr(),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: cs.primary),
                ),
              ],
            ),
          ),
          ...List.generate(3, (i) {
            final paymentMonth = DateTime(
              firstPayment.year,
              firstPayment.month + i,
            );
            final label =
                '${paymentMonth.month.toString().padLeft(2, '0')}/${paymentMonth.year}';
            return _PaymentRow(
              monthLabel: label,
              amount: MoneyUtils.formatMinor(monthlyMinor, currency: currency),
              theme: theme,
              cs: cs,
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.all_inclusive,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'cashback.perpetual_note'.tr(),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.monthLabel,
    required this.amount,
    required this.theme,
    required this.cs,
  });

  final String monthLabel;
  final String amount;
  final ThemeData theme;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(monthLabel, style: theme.textTheme.bodySmall),
          Text(
            amount,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}
