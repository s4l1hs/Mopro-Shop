import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/core/utils/coin_formatter.dart';

class CashbackChip extends StatelessWidget {
  const CashbackChip({
    required this.monthlyCoinMinor,
    required this.currency,
    super.key,
  });

  final int monthlyCoinMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.currency_exchange,
            size: 12,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'cashback.monthly_coin'.tr(
                namedArgs: {
                  'amount':
                      formatCoin(monthlyCoinMinor, currency, compact: true),
                },
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
