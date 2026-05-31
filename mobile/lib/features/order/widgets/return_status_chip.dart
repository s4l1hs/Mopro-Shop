import 'package:flutter/material.dart';
import 'package:mopro/features/order/data/return_dto.dart';

/// Status chip for a return's lifecycle (pending/approved/rejected/refunded).
class ReturnStatusChip extends StatelessWidget {
  const ReturnStatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (bg, fg) = switch (status) {
      ReturnLifecycle.approved => (cs.tertiaryContainer, cs.onTertiaryContainer),
      ReturnLifecycle.refunded => (cs.primaryContainer, cs.onPrimaryContainer),
      ReturnLifecycle.rejected => (cs.errorContainer, cs.onErrorContainer),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Chip(
      label: Text(
        ReturnLifecycle.label(status),
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
      backgroundColor: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}
