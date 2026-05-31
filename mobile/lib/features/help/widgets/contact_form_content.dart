import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/help/data/help_dto.dart';
import 'package:mopro/features/help/data/help_repository.dart';
import 'package:mopro/features/order/application/orders_provider.dart';

/// Presenter-agnostic contact form. Creates a support ticket; on success swaps
/// to a read-only success state with the ticket id + response-window copy.
class ContactFormContent extends ConsumerStatefulWidget {
  const ContactFormContent({
    this.initialCategory,
    this.initialOrderId,
    this.articleSlug,
    this.articleTitle,
    super.key,
  });

  final String? initialCategory;
  final int? initialOrderId;
  final String? articleSlug;
  final String? articleTitle;

  @override
  ConsumerState<ContactFormContent> createState() => _ContactFormContentState();
}

class _ContactFormContentState extends ConsumerState<ContactFormContent> {
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String? _category;
  int? _orderId;
  bool _emailPrefilled = false;
  bool _submitting = false;
  String? _error;
  TicketDto? _success;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _orderId = widget.initialOrderId;
    if (widget.articleTitle != null && widget.articleTitle!.isNotEmpty) {
      _subject.text = 'help.contact_article_subject'.tr(args: [widget.articleTitle!]);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _valid =>
      _emailValid(_email.text) &&
      _category != null &&
      _subject.text.trim().isNotEmpty &&
      _subject.text.length <= 100 &&
      _body.text.trim().isNotEmpty &&
      _body.text.length <= 2000;

  bool _emailValid(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  bool get _showOrderPicker =>
      _category == TicketCategory.orderIssue || _category == TicketCategory.returns;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ticket = await ref.read(helpRepositoryProvider).createTicket(
            CreateTicketRequest(
              email: _email.text.trim(),
              subject: _subject.text.trim(),
              body: _body.text.trim(),
              category: _category!,
              relatedOrderId: _showOrderPicker ? _orderId : null,
              relatedArticleSlug: widget.articleSlug,
            ),
          );
      if (mounted) setState(() => _success = ticket);
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'help.contact_error'.tr();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success != null) return _SuccessState(ticketId: _success!.id);

    final theme = Theme.of(context);
    // Prefill email once from the authenticated user (editable).
    final userEmail = ref.watch(currentUserProvider).valueOrNull?.email;
    if (!_emailPrefilled && userEmail != null && userEmail.isNotEmpty && _email.text.isEmpty) {
      _email.text = userEmail;
      _emailPrefilled = true;
    }
    final orders = ref.watch(ordersProvider).orders.valueOrNull ?? const [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _email,
          enabled: !_submitting,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'help.contact_email'.tr(),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: InputDecoration(
            labelText: 'help.contact_category'.tr(),
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final c in TicketCategory.all)
              DropdownMenuItem(value: c, child: Text(TicketCategory.label(c))),
          ],
          onChanged: _submitting ? null : (v) => setState(() => _category = v),
        ),
        if (_showOrderPicker && orders.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _orderId,
            decoration: InputDecoration(
              labelText: 'help.contact_related_order'.tr(),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final o in orders)
                DropdownMenuItem(
                  value: o.id,
                  child: Text(
                    'help.contact_order_label'.tr(
                      args: ['${o.id}', DateFormat('dd.MM.yyyy').format(o.createdAt)],
                    ),
                  ),
                ),
            ],
            onChanged: _submitting ? null : (v) => setState(() => _orderId = v),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _subject,
          enabled: !_submitting,
          maxLength: 100,
          buildCounter: _counterAbove(80),
          decoration: InputDecoration(
            labelText: 'help.contact_subject'.tr(),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _body,
          enabled: !_submitting,
          maxLines: 5,
          maxLength: 2000,
          buildCounter: _counterAbove(1800),
          decoration: InputDecoration(
            labelText: 'help.contact_body'.tr(),
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: (_valid && !_submitting) ? _submit : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('help.contact_submit'.tr()),
        ),
      ],
    );
  }

  // Char counter shown only at/above [threshold].
  InputCounterWidgetBuilder _counterAbove(int threshold) {
    return (context, {required currentLength, required isFocused, maxLength}) {
      if (currentLength < threshold) return const SizedBox.shrink();
      return Text(
        '$currentLength/$maxLength',
        style: Theme.of(context).textTheme.bodySmall,
      );
    };
  }
}

class _SuccessState extends StatelessWidget {
  const _SuccessState({required this.ticketId});
  final int ticketId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'help.contact_success_title'.tr(),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'help.contact_ticket_no'.tr(args: ['$ticketId']),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'help.contact_success_sub'.tr(),
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
