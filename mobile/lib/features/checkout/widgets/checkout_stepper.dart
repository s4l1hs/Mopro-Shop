import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class CheckoutStepper extends StatelessWidget {
  const CheckoutStepper({required this.currentStep, super.key});

  /// 0-based index: 0 = address, 1 = payment, 2 = review
  final int currentStep;

  static const _stepCount = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labels = [
      'checkout.step_address'.tr(),
      'checkout.step_payment'.tr(),
      'checkout.step_review'.tr(),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: List.generate(_stepCount * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIdx = i ~/ 2;
            final done = stepIdx < currentStep;
            return Expanded(
              child: Container(
                height: 2,
                color: done ? cs.primary : cs.outlineVariant,
              ),
            );
          }
          final stepIdx = i ~/ 2;
          final done = stepIdx < currentStep;
          final active = stepIdx == currentStep;
          return _StepDot(
            index: stepIdx,
            label: labels[stepIdx],
            done: done,
            active: active,
            theme: theme,
          );
        }),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.done,
    required this.active,
    required this.theme,
  });

  final int index;
  final String label;
  final bool done;
  final bool active;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final dotColor = done || active ? cs.primary : cs.outlineVariant;
    final textColor = done || active ? cs.primary : cs.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (done || active) ? dotColor : Colors.transparent,
            border: Border.all(color: dotColor, width: 2),
          ),
          alignment: Alignment.center,
          child: done
              ? Icon(Icons.check, size: 16, color: cs.onPrimary)
              : Text(
                  '${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: active ? cs.onPrimary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: textColor),
        ),
      ],
    );
  }
}
