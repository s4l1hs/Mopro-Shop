import 'package:flutter/material.dart';
import 'package:mopro/utils/money.dart';

/// Displays the monthly cashback amount computed from price + commission bps.
/// Uses MoneyUtils.cashbackMonthlyMinor — do NOT recompute inline.
class CashbackChip extends StatelessWidget {
  const CashbackChip({
    required this.priceMinor,
    required this.commissionBps,
    this.currency = 'TRY_COIN',
    super.key,
  });

  final int priceMinor;
  final int commissionBps;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monthly = MoneyUtils.cashbackMonthlyMinor(priceMinor, commissionBps);
    if (monthly <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.currency_exchange, size: 12, color: cs.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            '+${MoneyUtils.formatMinor(monthly, currency: currency)}/ay',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
