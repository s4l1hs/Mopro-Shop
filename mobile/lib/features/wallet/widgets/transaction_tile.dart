import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/core/utils/coin_formatter.dart';
import 'package:mopro_api/mopro_api.dart';

/// A single row in the wallet transaction history list.
class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.transaction, super.key});

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCredit =
        transaction.type == WalletTransactionTypeEnum.credit;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isCredit
            ? colorScheme.primaryContainer
            : colorScheme.secondaryContainer,
        child: Icon(
          isCredit
              ? Icons.arrow_downward_rounded
              : Icons.arrow_upward_rounded,
          color: isCredit
              ? colorScheme.primary
              : colorScheme.secondary,
          size: 20,
        ),
      ),
      title: Text(
        _typeLabel(transaction.type),
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        _formatDate(transaction.occurredAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        formatCoin(transaction.amountMinor, transaction.currency),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isCredit ? colorScheme.primary : null,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _typeLabel(WalletTransactionTypeEnum type) =>
      switch (type) {
        WalletTransactionTypeEnum.credit =>
          'wallet.transaction_type_cashback'.tr(),
        WalletTransactionTypeEnum.debit =>
          'wallet.transaction_type_other'.tr(),
      };

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.'
      '${dt.month.toString().padLeft(2, '0')}.'
      '${dt.year}';
}
