import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/utils/relative_time.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';
import 'package:mopro/features/seller/providers/seller_returns_provider.dart';
import 'package:mopro/utils/money.dart';

/// `/seller/returns` — seller returns inbox with status filter chips.
class SellerReturnsInboxScreen extends ConsumerStatefulWidget {
  const SellerReturnsInboxScreen({this.initialStatus = 'submitted', super.key});

  final String initialStatus;

  @override
  ConsumerState<SellerReturnsInboxScreen> createState() =>
      _SellerReturnsInboxScreenState();
}

class _SellerReturnsInboxScreenState
    extends ConsumerState<SellerReturnsInboxScreen> {
  late String _status = widget.initialStatus;

  static const _filters = [
    ('submitted', 'seller.filter_pending'),
    ('approved', 'seller.filter_approved'),
    ('rejected', 'seller.filter_rejected'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sellerReturnsInboxProvider(_status));
    final notifier = ref.read(sellerReturnsInboxProvider(_status).notifier);

    final body = state.loading
        ? const Center(child: CircularProgressIndicator())
        : (state.error != null && state.items.isEmpty)
            ? _Error(onRetry: notifier.refresh)
            : state.items.isEmpty
                ? Center(child: Text('seller.returns_empty'.tr()))
                : _list(state, notifier);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in _filters)
                ChoiceChip(
                  label: Text(label.tr()),
                  selected: _status == value,
                  onSelected: (_) => setState(() => _status = value),
                ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text('seller.returns_title'.tr())),
      body: context.isMobile ? content : CenteredContentColumn(child: content),
    );
  }

  Widget _list(SellerReturnsState state, SellerReturnsNotifier notifier) {
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.items.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (context, i) {
          if (i == state.items.length) {
            if (!state.hasMore) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: state.loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: notifier.loadMore,
                        child: Text('seller.load_more'.tr()),
                      ),
              ),
            );
          }
          return _ReturnCard(item: state.items[i]);
        },
      ),
    );
  }
}

class _ReturnCard extends StatelessWidget {
  const _ReturnCard({required this.item});
  final SellerReturn item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        'seller.customer_label'.tr(namedArgs: {'id': '${item.orderId}'}),
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.reason, style: theme.textTheme.bodySmall),
          Text(
            MoneyUtils.formatMinor(
              item.refundAmountMinor,
              currency: item.refundCurrency,
            ),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(relativeTime(item.createdAt), style: theme.textTheme.bodySmall),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/seller/returns/${item.id}', extra: item),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('seller.error_generic'.tr()),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text('seller.load_more'.tr())),
          ],
        ),
      );
}
