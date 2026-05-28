import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/order_status_chip.dart';

class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({required this.order, super.key});

  final OrderDto order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final moneyFmt = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );
    final dateFmt = DateFormat('dd.MM.yyyy', 'tr_TR');

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/orders/${order.id}'),
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
                    style: theme.textTheme.titleSmall,
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
              if (order.items.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${order.items.take(2).map((i) => i.title).join(', ')}'
                  '${order.items.length > 2 ? ' +${order.items.length - 2}' : ''}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'order.item_count'.tr(
                      namedArgs: {'count': '${order.items.length}'},
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    moneyFmt.format(order.totalMinor / 100.0),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
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
