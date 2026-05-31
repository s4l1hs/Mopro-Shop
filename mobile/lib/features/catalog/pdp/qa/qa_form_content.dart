import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_provider.dart';

/// Presenter-agnostic "ask a question" form: a single required body field.
/// Pops the surrounding modal with `true` on a successful submit.
class QuestionFormContent extends ConsumerStatefulWidget {
  const QuestionFormContent({required this.productId, super.key});

  final int productId;

  @override
  ConsumerState<QuestionFormContent> createState() =>
      _QuestionFormContentState();
}

class _QuestionFormContentState extends ConsumerState<QuestionFormContent> {
  @override
  Widget build(BuildContext context) {
    return _QaForm(
      title: 'qa.ask_title'.tr(),
      hint: 'qa.ask_hint'.tr(),
      submitLabel: 'qa.ask_submit'.tr(),
      maxLength: 500,
      onSubmit: (body) => ref.read(qaRepositoryProvider).ask(
            widget.productId,
            body: body,
            locale: EasyLocalization.of(context)?.locale.languageCode ?? 'tr',
          ),
    );
  }
}

/// Presenter-agnostic "answer" form: a single required body field.
class AnswerFormContent extends ConsumerStatefulWidget {
  const AnswerFormContent({
    required this.productId,
    required this.questionId,
    super.key,
  });

  final int productId;
  final int questionId;

  @override
  ConsumerState<AnswerFormContent> createState() => _AnswerFormContentState();
}

class _AnswerFormContentState extends ConsumerState<AnswerFormContent> {
  @override
  Widget build(BuildContext context) {
    return _QaForm(
      title: 'qa.answer_title'.tr(),
      hint: 'qa.answer_hint'.tr(),
      submitLabel: 'qa.answer_submit'.tr(),
      maxLength: 1000,
      onSubmit: (body) => ref.read(qaRepositoryProvider).answer(
            widget.productId,
            widget.questionId,
            body: body,
            locale: EasyLocalization.of(context)?.locale.languageCode ?? 'tr',
          ),
    );
  }
}

/// Shared body-only form used by both the ask and answer flows.
class _QaForm extends StatefulWidget {
  const _QaForm({
    required this.title,
    required this.hint,
    required this.submitLabel,
    required this.maxLength,
    required this.onSubmit,
  });

  final String title;
  final String hint;
  final String submitLabel;
  final int maxLength;
  final Future<void> Function(String body) onSubmit;

  @override
  State<_QaForm> createState() => _QaFormState();
}

class _QaFormState extends State<_QaForm> {
  final _body = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'qa.body_required'.tr());
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await widget.onSubmit(body);
      navigator.pop(true);
    } catch (_) {
      setState(() {
        _submitting = false;
        _error = 'qa.action_failed'.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _body,
          maxLength: widget.maxLength,
          minLines: 3,
          maxLines: 6,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.hint,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(widget.submitLabel),
          ),
        ),
      ],
    );
  }
}
