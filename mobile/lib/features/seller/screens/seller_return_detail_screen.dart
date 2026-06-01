import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/utils/relative_time.dart';
import 'package:mopro/core/widgets/adaptive_modal.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';
import 'package:mopro/features/seller/providers/seller_returns_provider.dart';
import 'package:mopro/utils/money.dart';

const _rejectReasons = [
  ('not_as_returned', 'seller.reject_reason_not_as_returned'),
  ('outside_policy', 'seller.reject_reason_outside_policy'),
  ('damaged_by_customer', 'seller.reject_reason_damaged_by_customer'),
  ('other', 'seller.reject_reason_other'),
];

/// `/seller/returns/:id` — return detail with approve/reject. Renders from the
/// inbox header passed via `extra`, or fetches by id (deep-link).
class SellerReturnDetailScreen extends ConsumerStatefulWidget {
  const SellerReturnDetailScreen({required this.returnId, this.initial, super.key});

  final int returnId;
  final SellerReturn? initial;

  @override
  ConsumerState<SellerReturnDetailScreen> createState() =>
      _SellerReturnDetailScreenState();
}

class _SellerReturnDetailScreenState
    extends ConsumerState<SellerReturnDetailScreen> {
  SellerReturn? _return;
  bool _busy = false;

  String _money(SellerReturn r) =>
      MoneyUtils.formatMinor(r.refundAmountMinor, currency: r.refundCurrency);

  @override
  void initState() {
    super.initState();
    _return = widget.initial;
  }

  Future<void> _approve(SellerReturn r) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('seller.approve_confirm_title'.tr()),
        content: Text(
          'seller.approve_confirm_body'.tr(namedArgs: {'amount': _money(r)}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('seller.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('seller.approve'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(sellerRepositoryProvider).approveReturn(r.id);
      ref.invalidate(sellerReturnsInboxProvider);
      if (!mounted) return;
      setState(() => _return = r.copyWith(status: 'approved'));
      messenger.showSnackBar(
        SnackBar(content: Text('seller.approved_toast'.tr())),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text('seller.error_generic'.tr())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(SellerReturn r) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showAdaptiveModal<({String code, String note})>(
      context,
      builder: (ctx) => _RejectForm(),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(sellerRepositoryProvider)
          .rejectReturn(r.id, result.code, result.note);
      ref.invalidate(sellerReturnsInboxProvider);
      if (!mounted) return;
      setState(() => _return = r.copyWith(status: 'rejected'));
      messenger.showSnackBar(
        SnackBar(content: Text('seller.rejected_toast'.tr())),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text('seller.error_generic'.tr())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _return;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'seller.return_detail_title'.tr(namedArgs: {'id': '${widget.returnId}'}),
        ),
      ),
      body: r != null
          ? _body(r)
          : ref.watch(sellerReturnByIdProvider(widget.returnId)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(child: Text('seller.error_generic'.tr())),
                data: (fetched) => fetched == null
                    ? Center(child: Text('seller.returns_empty'.tr()))
                    : _body(fetched),
              ),
    );
  }

  Widget _body(SellerReturn r) {
    final theme = Theme.of(context);
    final isPending = r.status == 'submitted';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'seller.customer_label'.tr(namedArgs: {'id': '${r.orderId}'}),
                style: theme.textTheme.titleMedium,
              ),
            ),
            _StatusChip(status: r.status),
          ],
        ),
        const SizedBox(height: 8),
        Text(relativeTime(r.createdAt), style: theme.textTheme.bodySmall),
        const Divider(height: 24),
        Text(r.reason, style: theme.textTheme.bodyMedium),
        if (r.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('seller.buyer_note'.tr(), style: theme.textTheme.labelMedium),
          Text(r.description, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 8),
        Text(
          'seller.refund_estimate'.tr(namedArgs: {'amount': _money(r)}),
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        if (isPending)
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _approve(r),
                  child: Text('seller.approve'.tr()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _reject(r),
                  child: Text('seller.reject'.tr()),
                ),
              ),
            ],
          )
        else
          _StatusBanner(status: r.status, when: relativeTime(r.createdAt)),
      ],
    );
  }

}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Chip(
        label: Text('seller.status_$status'.tr()),
        visualDensity: VisualDensity.compact,
      );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.when});
  final String status;
  final String when;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final approved = status == 'approved';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (approved ? cs.primary : cs.error).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            approved ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: approved ? cs.primary : cs.error,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('${'seller.status_$status'.tr()} · $when')),
        ],
      ),
    );
  }
}

class _RejectForm extends StatefulWidget {
  @override
  State<_RejectForm> createState() => _RejectFormState();
}

class _RejectFormState extends State<_RejectForm> {
  String _code = _rejectReasons.first.$1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'seller.reject_title'.tr(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _code,
          items: [
            for (final (value, label) in _rejectReasons)
              DropdownMenuItem(value: value, child: Text(label.tr())),
          ],
          onChanged: (v) => setState(() => _code = v ?? _code),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLength: 300,
          decoration: InputDecoration(labelText: 'seller.reject_note_hint'.tr()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('seller.cancel'.tr()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context)
                    .pop((code: _code, note: _note.text.trim())),
                child: Text('seller.reject'.tr()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
