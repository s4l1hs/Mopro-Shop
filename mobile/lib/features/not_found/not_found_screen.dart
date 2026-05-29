import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';

/// Branded 404 page. Wired into GoRouter's `errorBuilder` so every
/// unknown path renders this instead of the default Flutter error chrome.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, this.attemptedPath});

  final String? attemptedPath;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Title(
      title: 'Mopro · 404',
      color: MoproTokens.primaryLight,
      child: Scaffold(
        body: CenteredContentColumn(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: MoproTokens.primaryLight.withAlpha(26),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.search_off_rounded,
                    size: 48,
                    color: MoproTokens.primaryLight,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '404',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'errors.not_found_title'.tr(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'errors.not_found_subtitle'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (attemptedPath != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    attemptedPath!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => context.go('/'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MoproTokens.primaryLight,
                  ),
                  icon: const Icon(Icons.home_outlined),
                  label: Text('errors.not_found_cta'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
