import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/order/data/order_dto.dart';

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (bg, fg) = switch (status) {
      OrderStatus.pendingPayment => (
          cs.secondaryContainer,
          cs.onSecondaryContainer,
        ),
      OrderStatus.paid => (cs.tertiaryContainer, cs.onTertiaryContainer),
      OrderStatus.shipped => (
          cs.primaryContainer,
          cs.onPrimaryContainer,
        ),
      OrderStatus.delivered => (cs.primary, cs.onPrimary),
      OrderStatus.cancelled || OrderStatus.refunded => (
          cs.errorContainer,
          cs.onErrorContainer,
        ),
      OrderStatus.partiallyRefunded => (
          cs.surfaceContainerHighest,
          cs.onSurface,
        ),
      _ => (cs.surfaceContainerHighest, cs.onSurface),
    };

    return Chip(
      label: Text(
        OrderStatus.label(status),
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
      backgroundColor: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}

class OrderStatusTimeline extends StatelessWidget {
  const OrderStatusTimeline({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final timeline = OrderStatus.timeline;
    final currentIndex = timeline.indexOf(status);
    final isCancelled = status == OrderStatus.cancelled ||
        status == OrderStatus.refunded ||
        status == OrderStatus.partiallyRefunded;

    if (isCancelled) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cancel_outlined, color: cs.error, size: 20),
            const SizedBox(width: 8),
            Text(
              OrderStatus.label(status),
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
            ),
          ],
        ),
      );
    }

    return Row(
      children: List.generate(timeline.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIndex = i ~/ 2;
          final isCompleted = stepIndex < currentIndex;
          return Expanded(
            child: Divider(
              height: 2,
              thickness: 2,
              color: isCompleted ? cs.primary : cs.outlineVariant,
            ),
          );
        }
        final stepIndex = i ~/ 2;
        final isCompleted = stepIndex <= currentIndex;
        final isCurrent = stepIndex == currentIndex;
        return _TimelineStep(
          label: _stepLabel(stepIndex),
          isCompleted: isCompleted,
          isCurrent: isCurrent,
        );
      }),
    );
  }

  String _stepLabel(int index) {
    return switch (OrderStatus.timeline[index]) {
      OrderStatus.pendingPayment => 'order.step_payment'.tr(),
      OrderStatus.paid => 'order.step_paid'.tr(),
      OrderStatus.shipped => 'order.step_shipped'.tr(),
      OrderStatus.delivered => 'order.step_delivered'.tr(),
      _ => '',
    };
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.isCompleted,
    required this.isCurrent,
  });

  final String label;
  final bool isCompleted;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isCompleted ? cs.primary : cs.outlineVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted ? cs.primary : cs.surface,
            border: Border.all(color: color, width: 2),
          ),
          child: isCompleted
              ? Icon(Icons.check, size: 12, color: cs.onPrimary)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isCompleted ? cs.primary : cs.outlineVariant,
                fontWeight:
                    isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
