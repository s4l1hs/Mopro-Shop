import 'package:flutter/material.dart';
import 'package:mopro/design/tokens.dart';

/// Shared discount badge for the product card and the PDP price block.
///
/// Renders `%<percent>` on the design system's semantic *destructive* colour —
/// `tokens.dart` explicitly designates `destructive*` as the discount-badge
/// colour, and the theme maps it to `colorScheme.error`. Before P-006 the two
/// surfaces diverged: the card used a one-off red hex (`0xFFE53935`) and the
/// PDP used brand orange (`cs.primary`). This widget is the single source of
/// truth so they stay consistent and theme-aware.
class DiscountPill extends StatelessWidget {
  const DiscountPill({required this.percent, super.key});

  /// Whole-number discount percentage (e.g. `20` → "%20").
  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(MoproTokens.radiusSm),
      ),
      child: Text(
        '%$percent',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onError,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
