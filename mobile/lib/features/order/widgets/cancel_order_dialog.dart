import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/design/responsive/breakpoint_resolver.dart';

/// Cancellation reason codes (small enum, free-text `note` when "other").
class CancelReason {
  static const changedMind = 'changed_mind';
  static const foundBetterPrice = 'found_better_price';
  static const shippingTooSlow = 'shipping_too_slow';
  static const accidentalOrder = 'accidental_order';
  static const other = 'other';

  static const all = [
    changedMind,
    foundBetterPrice,
    shippingTooSlow,
    accidentalOrder,
    other,
  ];

  static String label(String code) => 'returns.cancel_reason_$code'.tr();
}

/// Presents the cancel-order confirmation adaptively: a dialog on `>=600` and a
/// bottom sheet on mobile, both rendering [CancelOrderContent]. Returns `true`
/// when the order was cancelled. [onConfirm] performs the cancel and throws on
/// failure (so the content can stay open and surface the error).
Future<bool?> showCancelOrderDialog(
  BuildContext context, {
  required Future<void> Function(String reason, String note) onConfirm,
  bool refundIsWallet = false,
  bool refundKnown = false,
}) {
  final content = CancelOrderContent(
    onConfirm: onConfirm,
    refundIsWallet: refundIsWallet,
    refundKnown: refundKnown,
  );
  if (context.isMobile) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: content,
        ),
      ),
    );
  }
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(padding: const EdgeInsets.all(24), child: content),
      ),
    ),
  );
}

/// Presenter-agnostic cancel content: title, refund sub-copy, required reason
/// picker, optional note (when "other"), and Keep/Cancel actions.
class CancelOrderContent extends StatefulWidget {
  const CancelOrderContent({
    required this.onConfirm,
    this.refundIsWallet = false,
    this.refundKnown = false,
    super.key,
  });

  final Future<void> Function(String reason, String note) onConfirm;
  final bool refundIsWallet;
  final bool refundKnown;

  @override
  State<CancelOrderContent> createState() => _CancelOrderContentState();
}

class _CancelOrderContentState extends State<CancelOrderContent> {
  String? _reason;
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String get _subcopyKey {
    if (!widget.refundKnown) return 'returns.cancel_subcopy_plain';
    return widget.refundIsWallet
        ? 'returns.cancel_subcopy_wallet'
        : 'returns.cancel_subcopy_card';
  }

  Future<void> _submit() async {
    if (_reason == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onConfirm(_reason!, _noteCtrl.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'returns.cancel_error_generic'.tr();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'returns.cancel_title'.tr(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _subcopyKey.tr(),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
          ),
          const SizedBox(height: 8),
        ],
        DropdownButtonFormField<String>(
          initialValue: _reason,
          decoration: InputDecoration(
            labelText: 'returns.cancel_reason_label'.tr(),
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final code in CancelReason.all)
              DropdownMenuItem(value: code, child: Text(CancelReason.label(code))),
          ],
          onChanged: _submitting
              ? null
              : (v) => setState(() => _reason = v),
        ),
        if (_reason == CancelReason.other) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            enabled: !_submitting,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'returns.cancel_note_label'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _submitting ? null : () => Navigator.of(context).pop(false),
                child: Text('returns.keep'.tr()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: (_reason == null || _submitting) ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('order.cancel'.tr()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
