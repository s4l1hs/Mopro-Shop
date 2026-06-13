import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/features/account/providers/fit_profile_provider.dart';

/// Size-fit phase 1: the PDP "your size" card under the variant selector.
/// - ok → "Önerilen beden: M" + signal copy + the "yaklaşık" (approximate) flag
///   (the seed charts are representative — phase-1 honesty requirement).
/// - no_profile / incomplete_profile → CTA to the Account fit form.
/// - no_chart / guest / loading / error → renders nothing (enrichment, never a
///   blocker — the membership-card pattern).
class PdpSizeRecommendation extends ConsumerWidget {
  const PdpSizeRecommendation({required this.productId, super.key});

  final int productId;

  static String _signalCopy(String? signal, String? lower, String? upper) {
    switch (signal) {
      case 'between':
        return 'fit.signal_between'
            .tr(namedArgs: {'lower': lower ?? '', 'upper': upper ?? ''});
      case 'size_up':
        return 'fit.signal_size_up'.tr();
      case 'size_down':
        return 'fit.signal_size_down'.tr();
      default:
        return 'fit.signal_true_to_size'.tr();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed =
        ref.watch(authNotifierProvider).valueOrNull is AuthAuthenticated;
    if (!authed) return const SizedBox.shrink();

    final rec = ref.watch(sizeRecommendationProvider(productId)).valueOrNull;
    if (rec == null || rec.status == 'no_chart') {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget card(Widget child) => Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: child,
        );

    if (rec.status != 'ok') {
      // no_profile / incomplete_profile → invite to complete the fit profile.
      return card(Row(
        children: [
          Icon(Icons.straighten, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'fit.cta_complete_profile'.tr(),
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => context.push('/account/fit-profile'),
            child: Text('fit.cta_button'.tr()),
          ),
        ],
      ),);
    }

    return card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.straighten, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'fit.your_size'.tr(namedArgs: {'size': rec.size ?? ''}),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            // Provenance: a seller chart is the actual garment's table (per-brand
            // truth) → "sized by seller"; the standard baseline is approximate.
            // Never suppresses the BASIC warning below.
            if (rec.source_ == 'seller')
              _SellerChip(label: 'fit.sized_by_seller'.tr())
            else if (rec.chartApproximate)
              Text(
                'fit.approximate'.tr(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _signalCopy(rec.signal, rec.betweenLower, rec.betweenUpper),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        // BASIC tier (or any rec with estimated measurements): a clear
        // approximate warning — the estimate came from height/weight/gender,
        // not real measurements. DETAILED renders without this.
        if (rec.confidence == 'basic' ||
            (rec.estimated?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'fit.basic_warning'.tr(),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ],
    ),);
  }
}

/// A subtle "sized by seller" badge shown when the recommendation came from a
/// seller-entered chart (source == seller). Informational only.
class _SellerChip extends StatelessWidget {
  const _SellerChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_outlined,
            size: 12,
            color: cs.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}
