import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/order/application/returns_provider.dart';
import 'package:mopro/features/order/data/return_dto.dart';
import 'package:mopro/features/order/widgets/return_status_chip.dart';
import 'package:mopro/utils/money.dart';

class ReturnsListScreen extends ConsumerWidget {
  const ReturnsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(returnsProvider);
    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('returns.list_title'.tr())),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          final appError = err is AppError
              ? err
              : UnknownError(statusCode: 0, message: err.toString());
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () => ref.read(returnsProvider.notifier).refresh(),
            ),
          );
        },
        data: (returns) => returns.isEmpty
            ? _Empty(onGoOrders: () => context.go('/orders'))
            : RefreshIndicator(
                onRefresh: () => ref.read(returnsProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: returns.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _ReturnCard(item: returns[i]),
                ),
              ),
      ),
    );
  }
}

class _ReturnCard extends StatelessWidget {
  const _ReturnCard({required this.item});

  final ReturnListItemDto item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateFmt = DateFormat('dd.MM.yyyy');
    return Semantics(
      button: true,
      label: '${'returns.return_no'.tr()} #${item.id}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go('/returns/${item.id}'),
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
                    '${'returns.return_no'.tr()} #${item.id}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  ReturnStatusChip(status: item.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                dateFmt.format(item.createdAt.toLocal()),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    ReturnReason.label(item.reason),
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    MoneyUtils.formatMinor(
                      item.refundAmountMinor,
                      currency: item.refundCurrency,
                    ),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onGoOrders});

  final VoidCallback onGoOrders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.assignment_return_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('returns.empty'.tr(), style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onGoOrders,
              child: Text('returns.go_orders'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
