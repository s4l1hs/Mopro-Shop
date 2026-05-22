import 'package:flutter/material.dart';
import 'package:mopro/core/utils/coin_formatter.dart';

/// A compact tappable chip showing the user's coin balance.
/// Shown on HomeScreen as a bridge to the wallet flow.
class CoinBalancePill extends StatelessWidget {
  const CoinBalancePill({
    required this.amountMinor,
    required this.currency,
    required this.onTap,
    super.key,
  });

  final int amountMinor;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.toll_rounded,
                size: 18,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                formatCoin(amountMinor, currency),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
