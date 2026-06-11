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
        data: (returns) {
          if (returns.isEmpty) {
            return _Empty(onGoOrders: () => context.go('/orders'));
          }
          // RT-06: client-side status filter over the already-fetched list.
          // The bar only offers statuses present in the list, so a selected
          // filter always has matches — except if a refresh removes the last
          // return of the selected status, in which case we fall back to all.
          final selected = ref.watch(returnsStatusFilterProvider);
          final present = {for (final r in returns) r.status};
          final effective =
              (selected != null && present.contains(selected)) ? selected : null;
          final visible = effective == null
              ? returns
              : returns.where((r) => r.status == effective).toList();
          return RefreshIndicator(
            onRefresh: () => ref.read(returnsProvider.notifier).refresh(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusFilterBar(returns: returns),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _ReturnCard(item: visible[i]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// RT-06: a horizontal status-filter chip row. "All" plus one chip per status
/// actually present in the fetched list (so we never offer an empty filter).
class _StatusFilterBar extends ConsumerWidget {
  const _StatusFilterBar({required this.returns});

  final List<ReturnListItemDto> returns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Preserve the lifecycle order; only show statuses that occur in the list.
    const order = [
      ReturnLifecycle.pending,
      ReturnLifecycle.approved,
      ReturnLifecycle.rejected,
      ReturnLifecycle.refunded,
    ];
    final present = {for (final r in returns) r.status};
    final statuses = order.where(present.contains).toList();
    if (statuses.length < 2) {
      // Nothing meaningful to filter (all one status) — hide the bar entirely.
      return const SizedBox.shrink();
    }
    final selected = ref.watch(returnsStatusFilterProvider);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _FilterChip(
            label: 'returns.filter_all'.tr(),
            selected: selected == null,
            onSelected: () =>
                ref.read(returnsStatusFilterProvider.notifier).state = null,
          ),
          for (final s in statuses) ...[
            const SizedBox(width: 8),
            _FilterChip(
              label: ReturnLifecycle.label(s),
              selected: selected == s,
              onSelected: () =>
                  ref.read(returnsStatusFilterProvider.notifier).state = s,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
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
                  Flexible(
                    child: Text(
                      ReturnReason.label(item.reason),
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
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
