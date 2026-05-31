import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/widgets/adaptive_modal.dart';
import 'package:mopro/core/widgets/login_required_sheet.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_form_content.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_write_provider.dart';
import 'package:mopro/features/catalog/pdp/reviews/reviews_provider.dart';

/// Shared entry point for the review create/edit flow, used by all three call
/// sites (order detail, the PDP reviews tab, `/account/reviews`). Gates guests
/// through the adaptive login presenter, opens [ReviewFormContent] in the
/// adaptive modal, and on success invalidates the affected providers and shows
/// a confirmation SnackBar.
void openReviewForm(
  BuildContext context,
  WidgetRef ref, {
  required int productId,
  int? reviewId,
  int initialRating = 0,
  String initialTitle = '',
  String initialBody = '',
}) {
  requireAuth(
    context,
    ref,
    reason: 'reviews.login_to_vote'.tr(),
    onAuthed: () async {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await showAdaptiveModal<bool>(
        context,
        builder: (_) => ReviewFormContent(
          productId: productId,
          reviewId: reviewId,
          initialRating: initialRating,
          initialTitle: initialTitle,
          initialBody: initialBody,
        ),
      );
      if (ok ?? false) {
        ref
          ..invalidate(reviewsNotifierProvider(productId))
          ..invalidate(reviewEligibilityProvider(productId))
          ..invalidate(myReviewsProvider);
        messenger.showSnackBar(
          SnackBar(content: Text('reviews.submitted'.tr())),
        );
      }
    },
  );
}
