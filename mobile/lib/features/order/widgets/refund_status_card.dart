import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/utils/money.dart';

/// Read-only refund visibility card. Renders wherever an [OrderDto.refund] or a
/// return's refund is present (cancelled orders, approved returns).
class RefundStatusCard extends StatelessWidget {
  const RefundStatusCard({required this.refund, super.key});

  final RefundInfo refund;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateFmt = DateFormat('dd.MM.yyyy');

    final (chipBg, chipFg, chipLabel) = switch (refund.status) {
      RefundStatus.processing => (
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
          'returns.refund_status_processing'.tr(),
        ),
      RefundStatus.issued => (
          cs.primaryContainer,
          cs.onPrimaryContainer,
          'returns.refund_status_issued'.tr(),
        ),
      RefundStatus.failed => (
          cs.errorContainer,
          cs.onErrorContainer,
          'returns.refund_status_failed'.tr(),
        ),
      _ => (
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
          'returns.refund_status_pending'.tr(),
        ),
    };

    return Semantics(
      container: true,
      label: 'returns.refund_title'.tr(),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'returns.refund_title'.tr(),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Chip(
                  label: Text(
                    chipLabel,
                    style: theme.textTheme.labelSmall?.copyWith(color: chipFg),
                  ),
                  backgroundColor: chipBg,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row(
              theme,
              'returns.refund_amount'.tr(),
              MoneyUtils.formatMinor(refund.amountMinor, currency: refund.currency),
            ),
            const SizedBox(height: 8),
            _row(
              theme,
              'returns.refund_method'.tr(),
              refund.isWallet
                  ? 'returns.method_wallet'.tr()
                  : 'returns.method_original'.tr(),
            ),
            if (refund.status == RefundStatus.issued && refund.issuedAt != null) ...[
              const SizedBox(height: 8),
              _row(theme, 'returns.refund_issued_date'.tr(),
                  dateFmt.format(refund.issuedAt!.toLocal())),
            ] else if (refund.estimatedAt != null) ...[
              const SizedBox(height: 8),
              _row(theme, 'returns.refund_estimated'.tr(),
                  dateFmt.format(refund.estimatedAt!.toLocal())),
            ],
            if (refund.status == RefundStatus.failed) ...[
              const SizedBox(height: 8),
              Text(
                'returns.refund_failed_hint'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
