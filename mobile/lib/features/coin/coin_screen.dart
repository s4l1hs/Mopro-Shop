import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Coin tab placeholder (IA-01).
///
/// The Categories bottom-nav tab was replaced by this Coin tab. The full Coin
/// hub is built in IA-02; for now this is a routed, labeled placeholder so the
/// new tab resolves to a real screen.
class CoinScreen extends StatelessWidget {
  const CoinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('coin.placeholder_title'.tr())),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.monetization_on_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'coin.placeholder_title'.tr(),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'coin.placeholder_body'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
