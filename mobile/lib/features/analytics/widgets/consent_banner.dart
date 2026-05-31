import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/feature_flags.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';

/// First-visit analytics consent prompt (binary opt-in, Decision 3). Renders a
/// sticky bottom bar for authed users who haven't decided yet. Gated by
/// [kAnalyticsConsentEnabled]; hidden for guests and after any decision.
///
/// A11y (PR #20): the controls live in a [FocusTraversalGroup] so Tab cycles the
/// CTAs; there is intentionally no Escape-to-dismiss — the user must choose.
class ConsentBanner extends ConsumerWidget {
  const ConsentBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kAnalyticsConsentEnabled) return const SizedBox.shrink();
    final consent = ref.watch(userConsentProvider);
    if (consent.loading || !consent.authed || consent.decided) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Semantics(
      container: true,
      label: 'consent.banner_headline'.tr(),
      child: Material(
        color: cs.surface,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: FocusTraversalGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'consent.banner_headline'.tr(),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      for (final k in const [
                        'consent.banner_body_1',
                        'consent.banner_body_2',
                        'consent.banner_body_3',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            k.tr(),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: () => context.push(
                            '/help/article/privacy-and-tracking',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: cs.primary,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('consent.more_info'.tr()),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => ref
                                  .read(userConsentProvider.notifier)
                                  .setConsent(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cs.primary,
                                side: BorderSide(color: cs.primary),
                              ),
                              child: Text('consent.decline'.tr()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => ref
                                  .read(userConsentProvider.notifier)
                                  .setConsent(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.primary,
                                foregroundColor: cs.onPrimary,
                              ),
                              child: Text('consent.accept'.tr()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
