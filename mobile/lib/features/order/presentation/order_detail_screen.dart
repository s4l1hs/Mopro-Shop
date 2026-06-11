import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_submission.dart';
import 'package:mopro/features/order/application/order_detail_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_item_dto.dart';
import 'package:mopro/features/order/widgets/cashback_schedule.dart';
import 'package:mopro/features/order/widgets/order_eligibility_actions.dart';
import 'package:mopro/features/order/widgets/order_status_chip.dart';
import 'package:mopro/features/order/widgets/refund_status_card.dart';
import 'package:mopro/utils/money.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(
              title: Text('order.detail_title'.tr()),
            ),
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
              onRetry: () =>
                  ref.read(orderDetailProvider(orderId).notifier).refresh(),
            ),
          );
        },
        data: (order) => _OrderDetailBody(order: order, orderId: orderId),
      ),
    );
  }
}

class _OrderDetailBody extends ConsumerWidget {
  const _OrderDetailBody({required this.order, required this.orderId});

  final OrderDto order;
  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final moneyFmt = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(orderDetailProvider(orderId).notifier).refresh(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'order.number'.tr(namedArgs: {'id': '${order.id}'}),
                        style: theme.textTheme.titleMedium,
                      ),
                      OrderStatusChip(status: order.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dateFmt.format(order.createdAt.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'order.status_timeline'.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  OrderStatusTimeline(status: order.status),
                  const SizedBox(height: 24),
                  Text(
                    'order.items'.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _OrderItemRow(
                item: order.items[i],
                moneyFmt: moneyFmt,
                onReview: order.status == OrderStatus.delivered
                    ? () => openReviewForm(
                          context,
                          ref,
                          productId: order.items[i].productId,
                        )
                    : null,
              ),
              childCount: order.items.length,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  _PriceRow(
                    label: 'order.subtotal'.tr(),
                    value: moneyFmt.format(
                      (order.itemsMinor ?? order.totalMinor) / 100.0,
                    ),
                  ),
                  if (order.shippingMinor != null)
                    _PriceRow(
                      label: 'order.shipping'.tr(),
                      value: moneyFmt.format(order.shippingMinor! / 100.0),
                    ),
                  if (order.kdvMinor != null)
                    _PriceRow(
                      label: 'order.kdv'.tr(),
                      value: moneyFmt.format(order.kdvMinor! / 100.0),
                    ),
                  const Divider(),
                  _PriceRow(
                    label: 'order.total'.tr(),
                    value: moneyFmt.format(order.totalMinor / 100.0),
                    isTotal: true,
                  ),
                  const SizedBox(height: 24),
                  if (order.refund != null) ...[
                    RefundStatusCard(refund: order.refund!),
                    const SizedBox(height: 16),
                  ],
                  OrderEligibilityActions(order: order),
                  if ((order.actions?.canCancel ?? false) ||
                      (order.actions?.canReturn ?? false))
                    const SizedBox(height: 16),
                  // OR-04: reorder — re-add this order's items to the cart.
                  if (order.items.isNotEmpty) ...[
                    _ReorderButton(items: order.items),
                    const SizedBox(height: 16),
                  ],
                  // OR-07: per-order help entry → the help center (like AC-02).
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => context.push('/help'),
                      icon: const Icon(Icons.help_outline_rounded),
                      label: Text('order.help'.tr()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Cashback schedule ──────────────────────────────────
                  if (order.items.isNotEmpty) ...[
                    Text(
                      'cashback.schedule_title'.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (_) {
                        final totalMonthly = order.items.fold<int>(
                          0,
                          (sum, item) =>
                              sum +
                              MoneyUtils.cashbackMonthlyMinor(
                                item.priceMinor * item.qty,
                                item.commissionPctBps,
                              ),
                        );
                        if (totalMonthly <= 0) return const SizedBox.shrink();
                        return CashbackSchedule(
                          monthlyMinor: totalMonthly,
                          currency: order.currency.contains('COIN')
                              ? order.currency
                              : '${order.currency}_COIN',
                          startDate: order.deliveredAt != null
                              ? order.deliveredAt!.add(const Duration(days: 5))
                              : DateTime.now(),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({
    required this.item,
    required this.moneyFmt,
    this.onReview,
  });

  final OrderItemDto item;
  final NumberFormat moneyFmt;

  /// When non-null (delivered orders), renders a "Değerlendir" affordance that
  /// opens the review form for this item's product.
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.coverImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.coverImageUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder(cs),
                      )
                    : _placeholder(cs),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // OR-05: variant colour/size label (e.g. "Siyah, M").
                    if (item.variantLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.variantLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'order.qty_x_price'.tr(namedArgs: {
                        'qty': '${item.qty}',
                        'price': moneyFmt.format(item.priceMinor / 100.0),
                      },),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                moneyFmt.format(item.lineTotalMinor / 100.0),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (onReview != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(top: 8, start: 76),
                child: OutlinedButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.rate_review_outlined, size: 16),
                  label: Text('reviews.write_cta'.tr()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.primary,
                    side: BorderSide(color: cs.primary),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) => Container(
        width: 64,
        height: 64,
        color: cs.surfaceContainerHighest,
        child: Icon(
          Icons.image_outlined,
          size: 32,
          color: cs.outlineVariant,
        ),
      );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  final String label;
  final String value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final style = isTotal
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            )
        : Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// OR-04: re-adds an order's items to the cart via the existing add path, then
/// navigates to the cart. Per-item failures (out-of-stock / unavailable) are
/// counted and reported rather than aborting the whole reorder.
class _ReorderButton extends ConsumerStatefulWidget {
  const _ReorderButton({required this.items});

  final List<OrderItemDto> items;

  @override
  ConsumerState<_ReorderButton> createState() => _ReorderButtonState();
}

class _ReorderButtonState extends ConsumerState<_ReorderButton> {
  bool _busy = false;

  Future<void> _reorder() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final cart = ref.read(cartProvider.notifier);
    var added = 0;
    var failed = 0;
    for (final it in widget.items) {
      try {
        await cart.addItem(
          productId: it.productId,
          variantId: it.variantId,
          qty: it.qty,
        );
        added++;
      } on Object catch (_) {
        failed++; // out-of-stock / unavailable — skip this line
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final String msg;
    if (added == 0) {
      msg = 'order.reorder_none'.tr();
    } else if (failed > 0) {
      msg = 'order.reorder_partial'.tr(
        namedArgs: {
          'added': '$added',
          'failed': '$failed',
        },
      );
    } else {
      msg = 'order.reorder_done'.tr(namedArgs: {'count': '$added'});
    }
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    if (added > 0) router.go('/cart');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _reorder,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded),
        label: Text('order.reorder'.tr()),
      ),
    );
  }
}
