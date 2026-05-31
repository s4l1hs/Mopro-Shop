import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive_builder.dart';
import 'package:mopro/features/order/application/order_detail_provider.dart';
import 'package:mopro/features/order/application/return_flow_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/order_item_dto.dart';
import 'package:mopro/features/order/data/return_dto.dart';
import 'package:mopro/utils/money.dart';

/// Multi-step return request flow at `/orders/:id/return`. The current step is
/// mirrored into the URL `?step=` param (refresh / deep-link survive); browser
/// chrome + the in-flow back button move between steps; leaving step 1 with a
/// selection prompts an abandonment confirm.
class OrderReturnFlowScreen extends ConsumerStatefulWidget {
  const OrderReturnFlowScreen({
    required this.orderId,
    this.initialStep,
    super.key,
  });

  final int orderId;
  final String? initialStep;

  @override
  ConsumerState<OrderReturnFlowScreen> createState() =>
      _OrderReturnFlowScreenState();
}

class _OrderReturnFlowScreenState extends ConsumerState<OrderReturnFlowScreen> {
  @override
  void initState() {
    super.initState();
    final initial = returnStepFromName(widget.initialStep);
    if (initial != ReturnStep.items) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(returnFlowProvider(widget.orderId).notifier).goTo(initial);
      });
    }
  }

  void _go(ReturnStep step) {
    ref.read(returnFlowProvider(widget.orderId).notifier).goTo(step);
    context.go('/orders/${widget.orderId}/return?step=${step.name}');
  }

  Future<bool> _confirmAbandon() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('returns.abandon_title'.tr()),
        content: Text('returns.abandon_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('returns.keep'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    final flow = ref.watch(returnFlowProvider(widget.orderId));

    return orderAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: Text('returns.flow_title'.tr())),
        body: Center(child: Text('common.error'.tr())),
      ),
      data: (order) => _scaffold(context, order, flow),
    );
  }

  Widget _scaffold(BuildContext context, OrderDto order, ReturnFlowState flow) {
    final canLeave = flow.step == ReturnStep.confirm || !flow.hasSelection;
    return PopScope(
      canPop: canLeave,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (flow.step.index > ReturnStep.items.index &&
            flow.step != ReturnStep.confirm) {
          _go(ReturnStep.values[flow.step.index - 1]);
        } else if (await _confirmAbandon() && context.mounted) {
          context.go('/orders/${widget.orderId}');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('returns.flow_title'.tr()),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: _StepIndicator(step: flow.step),
          ),
        ),
        body: ResponsiveBuilder(
          mobile: (_) => _body(order, flow),
          desktop: (_) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _body(order, flow),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(OrderDto order, ReturnFlowState flow) {
    final notifier = ref.read(returnFlowProvider(widget.orderId).notifier);
    return switch (flow.step) {
      ReturnStep.items => _ItemsStep(
          order: order,
          flow: flow,
          notifier: notifier,
          onContinue: () => _go(ReturnStep.reasons),
        ),
      ReturnStep.reasons => _ReasonsStep(
          order: order,
          flow: flow,
          notifier: notifier,
          onContinue: () => _go(ReturnStep.review),
        ),
      ReturnStep.review => _ReviewStep(
          order: order,
          flow: flow,
          onSubmit: () => notifier.submit(widget.orderId),
        ),
      ReturnStep.confirm => _ConfirmStep(returnId: flow.createdReturnId),
    };
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});
  final ReturnStep step;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < ReturnStep.values.length; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step.index ? cs.primary : cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < ReturnStep.values.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

OrderItemDto? _itemById(OrderDto order, int id) {
  for (final it in order.items) {
    if (it.id == id) return it;
  }
  return null;
}

int _refundEstimateMinor(OrderDto order, Map<int, int> selected) {
  var total = 0;
  selected.forEach((id, qty) {
    final it = _itemById(order, id);
    if (it != null) total += it.priceMinor * qty;
  });
  return total;
}

// ── Step 1: item selection ────────────────────────────────────────────────────
class _ItemsStep extends StatelessWidget {
  const _ItemsStep({
    required this.order,
    required this.flow,
    required this.notifier,
    required this.onContinue,
  });

  final OrderDto order;
  final ReturnFlowState flow;
  final ReturnFlowNotifier notifier;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = order.actions;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'returns.select_items_title'.tr(),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              for (final item in order.items)
                _ItemRow(
                  item: item,
                  maxQty: actions?.maxQuantityFor(item.id) ?? 0,
                  selectedQty: flow.selected[item.id],
                  onToggle: () => notifier.toggleItem(item.id),
                  onQty: (q) => notifier.setQuantity(item.id, q),
                ),
            ],
          ),
        ),
        _BottomBar(
          caption: 'returns.items_selected'
              .tr(args: ['${flow.selected.length}']),
          enabled: flow.hasSelection,
          label: 'returns.continue_cta'.tr(),
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.maxQty,
    required this.selectedQty,
    required this.onToggle,
    required this.onQty,
  });

  final OrderItemDto item;
  final int maxQty;
  final int? selectedQty;
  final VoidCallback onToggle;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final returnable = maxQty > 0;
    final selected = selectedQty != null;
    return Opacity(
      opacity: returnable ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              onChanged: returnable ? (_) => onToggle() : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: theme.textTheme.bodyMedium),
                  if (!returnable)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Chip(
                        label: Text('returns.returned_chip'.tr()),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (selected && returnable)
                    _QtyStepper(
                      qty: selectedQty!,
                      max: maxQty,
                      onChanged: onQty,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.max,
    required this.onChanged,
  });
  final int qty;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 18),
          onPressed: qty > 1 ? () => onChanged(qty - 1) : null,
          tooltip: 'product.decrease_qty'.tr(),
        ),
        Text('$qty'),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          onPressed: qty < max ? () => onChanged(qty + 1) : null,
          tooltip: 'product.increase_qty'.tr(),
        ),
      ],
    );
  }
}

// ── Step 2: reasons ────────────────────────────────────────────────────────────
class _ReasonsStep extends StatelessWidget {
  const _ReasonsStep({
    required this.order,
    required this.flow,
    required this.notifier,
    required this.onContinue,
  });

  final OrderDto order;
  final ReturnFlowState flow;
  final ReturnFlowNotifier notifier;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final id in flow.selected.keys)
                _ReasonRow(
                  title: _itemById(order, id)?.title ?? '#$id',
                  reason: flow.reasons[id],
                  note: flow.notes[id] ?? '',
                  onReason: (r) => notifier.setReason(id, r),
                  onNote: (n) => notifier.setNote(id, n),
                ),
            ],
          ),
        ),
        _BottomBar(
          caption: '',
          enabled: flow.allReasonsSet,
          label: 'returns.continue_cta'.tr(),
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.title,
    required this.reason,
    required this.note,
    required this.onReason,
    required this.onNote,
  });

  final String title;
  final String? reason;
  final String note;
  final ValueChanged<String> onReason;
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: reason,
            decoration: InputDecoration(
              labelText: 'returns.reason_for_item'.tr(),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final code in ReturnReason.all)
                DropdownMenuItem(value: code, child: Text(ReturnReason.label(code))),
            ],
            onChanged: (v) => v != null ? onReason(v) : null,
          ),
          if (reason == ReturnReason.other) ...[
            const SizedBox(height: 8),
            TextField(
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'returns.note_optional'.tr(),
                border: const OutlineInputBorder(),
              ),
              onChanged: onNote,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Step 3: review ─────────────────────────────────────────────────────────────
class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.order,
    required this.flow,
    required this.onSubmit,
  });

  final OrderDto order;
  final ReturnFlowState flow;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estimate = _refundEstimateMinor(order, flow.selected);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('returns.review_title'.tr(), style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              for (final id in flow.selected.keys)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_itemById(order, id)?.title ?? '#$id'),
                  subtitle: Text(
                    '${'returns.items_count'.tr(args: ['${flow.selected[id]}'])}'
                    ' · ${ReturnReason.label(flow.reasons[id] ?? ReturnReason.other)}',
                  ),
                ),
              const Divider(),
              if (flow.error != null) ...[
                Text(
                  flow.error!.tr(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('returns.refund_estimate'.tr()),
                  Text(
                    MoneyUtils.formatMinor(estimate, currency: order.currency),
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('returns.refund_method_preview'.tr()),
                  Text(
                    (order.refund?.isWallet ?? false)
                        ? 'returns.method_wallet'.tr()
                        : 'returns.method_original'.tr(),
                  ),
                ],
              ),
            ],
          ),
        ),
        _BottomBar(
          caption: '',
          enabled: !flow.submitting,
          label: 'returns.submit'.tr(),
          busy: flow.submitting,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

// ── Step 4: confirmation ───────────────────────────────────────────────────────
class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({required this.returnId});
  final int? returnId;

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
              Icons.check_circle_outline,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'returns.confirm_title'.tr(),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'returns.confirm_subcopy'.tr(),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (returnId != null) ...[
              const SizedBox(height: 12),
              Text(
                'returns.tracking_no'.tr(args: ['$returnId']),
                style: theme.textTheme.titleSmall,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/returns'),
              child: Text('returns.my_returns_cta'.tr()),
            ),
            TextButton(
              onPressed: () => context.go('/'),
              child: Text('returns.back_home'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.caption,
    required this.enabled,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String caption;
  final bool enabled;
  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (caption.isNotEmpty)
              Expanded(
                child: Text(caption, style: theme.textTheme.bodyMedium),
              )
            else
              const Spacer(),
            FilledButton(
              onPressed: enabled ? onPressed : null,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
