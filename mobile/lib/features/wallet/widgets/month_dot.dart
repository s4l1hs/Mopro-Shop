import 'package:flutter/material.dart';
import 'package:mopro_api/mopro_api.dart';

/// 16 × 16 colour-coded circle representing a payment period status.
class MonthDot extends StatelessWidget {
  const MonthDot({required this.status, super.key});

  final CashbackPaymentStatusEnum status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      CashbackPaymentStatusEnum.paid => colorScheme.primary,
      CashbackPaymentStatusEnum.scheduled =>
        colorScheme.outlineVariant,
      CashbackPaymentStatusEnum.failed => colorScheme.error,
    };
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
