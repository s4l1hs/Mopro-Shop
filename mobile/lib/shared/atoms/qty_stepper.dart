import 'package:flutter/material.dart';

/// Compact +/qty/− stepper for cart line cards.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    required this.qty,
    required this.onDecrement,
    required this.onIncrement,
    this.minQty = 1,
    this.maxQty = 99,
    super.key,
  });

  final int qty;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final int minQty;
  final int maxQty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          onPressed: qty > minQty ? onDecrement : null,
          colorScheme: colorScheme,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$qty',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          onPressed: qty < maxQty ? onIncrement : null,
          colorScheme: colorScheme,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.colorScheme,
    this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: 16),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: onPressed != null
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          foregroundColor: onPressed != null
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurface.withAlpha(76),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}
