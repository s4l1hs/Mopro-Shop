import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum _EmptyStateVariant { empty, error, notFound }

class EmptyState extends StatelessWidget {
  const EmptyState._({
    required _EmptyStateVariant variant,
    this.onAction,
    Key? key,
  })  : _variant = variant,
        super(key: key);

  factory EmptyState.empty({VoidCallback? onAction, Key? key}) =>
      EmptyState._(variant: _EmptyStateVariant.empty, onAction: onAction, key: key);

  factory EmptyState.error({VoidCallback? onAction, Key? key}) =>
      EmptyState._(variant: _EmptyStateVariant.error, onAction: onAction, key: key);

  factory EmptyState.notFound({VoidCallback? onAction, Key? key}) =>
      EmptyState._(variant: _EmptyStateVariant.notFound, onAction: onAction, key: key);

  final _EmptyStateVariant _variant;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, messageKey, actionKey) = switch (_variant) {
      _EmptyStateVariant.empty => (
          Icons.inbox_outlined,
          'empty_state.empty_message',
          null,
        ),
      _EmptyStateVariant.error => (
          Icons.error_outline,
          'empty_state.error_message',
          'common.retry',
        ),
      _EmptyStateVariant.notFound => (
          Icons.search_off_outlined,
          'empty_state.not_found_message',
          null,
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            messageKey.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (onAction != null && actionKey != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onAction,
              child: Text(actionKey.tr()),
            ),
          ],
        ],
      ),
    );
  }
}
