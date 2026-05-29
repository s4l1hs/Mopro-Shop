import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/tokens.dart';

/// Presenter-agnostic "login required" content. Mounted in a bottom sheet
/// (mobile) or an `AuthCard` dialog (>=600) by `requireAuth`. While open it
/// listens for the user becoming authenticated and then dismisses + invokes
/// [onResume] — the resume-original-action contract from Session 1.
class LoginRequired extends ConsumerWidget {
  const LoginRequired({this.reason, this.onResume, super.key});

  final String? reason;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    ref.listen<AsyncValue<AuthState>>(authNotifierProvider, (_, next) {
      if (next.valueOrNull is AuthAuthenticated) {
        Navigator.of(context).pop();
        onResume?.call();
      }
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Illustration placeholder (lock badge) — distinct from AuthCard's logo.
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: MoproTokens.primaryLight.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            size: 34,
            color: MoproTokens.primaryLight,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'auth.login_required_title'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (reason != null) ...[
          const SizedBox(height: 8),
          Text(
            reason!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/auth/login');
            },
            child: Text('auth.login'.tr()),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/auth/register');
            },
            child: Text('auth.register'.tr()),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'auth.continue_as_guest'.tr(),
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
