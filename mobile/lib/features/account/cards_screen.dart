import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Stub: no saved cards yet
    return Scaffold(
      appBar: AppBar(title: Text('account.saved_cards'.tr())),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.credit_card_outlined,
              size: 64,
              color: cs.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'cards.empty'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'cards.empty_subtitle'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: wire to add card flow
        },
        icon: const Icon(Icons.add),
        label: Text('cards.add'.tr()),
      ),
    );
  }
}
