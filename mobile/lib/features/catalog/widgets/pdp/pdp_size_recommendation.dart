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
            Text(
              'fit.your_size'.tr(namedArgs: {'size': rec.size ?? ''}),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            // Phase-1 honesty: the chart is approximate, always say so.
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
      ],
    ),);
  }
}
