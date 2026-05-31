import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/order/application/order_detail_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/cancel_order_dialog.dart';

/// Renders the post-purchase action CTAs on the order detail screen, driven by
/// the server-computed [OrderDto.actions]. Renders nothing when no action is
/// available (no empty container).
class OrderEligibilityActions extends ConsumerWidget {
  const OrderEligibilityActions({required this.order, super.key});

  final OrderDto order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = order.actions;
    if (actions == null || (!actions.canCancel && !actions.canReturn)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final outline = OutlinedButton.styleFrom(
      foregroundColor: cs.primary,
      side: BorderSide(color: cs.primary),
      minimumSize: const Size.fromHeight(48),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (actions.canCancel) ...[
          OutlinedButton(
            style: outline,
            onPressed: () => _cancel(context, ref),
            child: Text('order.cancel'.tr()),
          ),
          const SizedBox(height: 8),
        ],
        if (actions.canReturn) ...[
          OutlinedButton(
            style: outline,
            onPressed: () => context.push('/orders/${order.id}/return'),
            child: Text('returns.create_cta'.tr()),
          ),
          const SizedBox(height: 8),
        ],
        if (actions.returnableUntil != null)
          Text(
            'returns.returnable_until'.tr(
              args: [DateFormat('dd.MM.yyyy').format(actions.returnableUntil!.toLocal())],
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
      ],
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final cancelled = await showCancelOrderDialog(
      context,
      refundKnown: order.refund != null,
      refundIsWallet: order.refund?.isWallet ?? false,
      onConfirm: (reason, note) => ref
          .read(orderDetailProvider(order.id).notifier)
          .cancelOrder(reason: reason, note: note),
    );
    if (cancelled ?? false) {
      messenger.showSnackBar(
        SnackBar(content: Text('returns.cancel_success'.tr())),
      );
    }
  }
}
