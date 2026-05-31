import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_write_provider.dart';

/// Presenter-agnostic review form: a 1–5 star picker, an optional title, and a
/// required body. Used for both create (POST) and edit (PUT) — pass [reviewId]
/// and the initial values to enter edit mode. Pops the surrounding modal with
/// `true` on a successful submit so the caller can refresh.
class ReviewFormContent extends ConsumerStatefulWidget {
  const ReviewFormContent({
    required this.productId,
    this.reviewId,
    this.initialRating = 0,
    this.initialTitle = '',
    this.initialBody = '',
    super.key,
  });

  final int productId;
  final int? reviewId;
  final int initialRating;
  final String initialTitle;
  final String initialBody;

  bool get isEdit => reviewId != null;

  @override
  ConsumerState<ReviewFormContent> createState() => _ReviewFormContentState();
}

class _ReviewFormContentState extends ConsumerState<ReviewFormContent> {
  late int _rating = widget.initialRating;
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);
  late final TextEditingController _body =
      TextEditingController(text: widget.initialBody);
  bool _submitting = false;
  String? _error;

  static const int _maxTitle = 100;
  static const int _maxBody = 2000;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _body.text.trim();
    if (_rating < 1 || _rating > 5) {
      setState(() => _error = 'reviews.form_rating_required'.tr());
      return;
    }
    if (body.isEmpty) {
      setState(() => _error = 'reviews.form_body_required'.tr());
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(reviewWriteRepositoryProvider);
    final locale = context.locale.languageCode;
    final navigator = Navigator.of(context);
    try {
      if (widget.isEdit) {
        await repo.update(
          widget.productId,
          widget.reviewId!,
          rating: _rating,
          title: _title.text.trim(),
          body: body,
          locale: locale,
        );
      } else {
        await repo.create(
          widget.productId,
          rating: _rating,
          title: _title.text.trim(),
          body: body,
          locale: locale,
        );
      }
      navigator.pop(true);
    } on ReviewAlreadyExists {
      // The user already reviewed this product (e.g. from another device).
      setState(() {
        _submitting = false;
        _error = 'reviews.form_already_exists'.tr();
      });
    } catch (_) {
      setState(() {
        _submitting = false;
        _error = 'reviews.action_failed'.tr();
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
          widget.isEdit
              ? 'reviews.form_title_edit'.tr()
              : 'reviews.form_title_new'.tr(),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _StarPicker(
          rating: _rating,
          onChanged: (v) => setState(() => _rating = v),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          maxLength: _maxTitle,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'reviews.form_title_label'.tr(),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _body,
          maxLength: _maxBody,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: 'reviews.form_body_label'.tr(),
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
                : Text(
                    widget.isEdit
                        ? 'reviews.form_submit_edit'.tr()
                        : 'reviews.form_submit_new'.tr(),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Tappable 1–5 star row used by the review form.
class _StarPicker extends StatelessWidget {
  const _StarPicker({required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            onPressed: () => onChanged(i),
            iconSize: 36,
            visualDensity: VisualDensity.compact,
            tooltip: '$i',
            icon: Icon(
              i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: i <= rating ? MoproTokens.ratingStar : cs.outlineVariant,
            ),
          ),
      ],
    );
  }
}
