import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/widgets/mopro_logo.dart';
import 'package:mopro/design/tokens.dart';

/// Shows a bottom sheet asking the user to log in or register.
/// [onAuthed] fires when the user returns authenticated.
/// [reason] is a short localized hint shown under the headline.
Future<void> showLoginRequiredSheet(
  BuildContext context, {
  String? reason,
  VoidCallback? onAuthed,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LoginRequiredSheet(reason: reason, onAuthed: onAuthed),
  );
}

/// Checks auth state. If authenticated, calls [onAuthed] immediately.
/// Otherwise shows [showLoginRequiredSheet].
void requireAuth(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onAuthed,
  String? reason,
}) {
  final authState = ref.read(authNotifierProvider).valueOrNull;
  if (authState is AuthAuthenticated) {
    onAuthed();
    return;
  }
  showLoginRequiredSheet(context, reason: reason, onAuthed: onAuthed);
}

class _LoginRequiredSheet extends ConsumerWidget {
  const _LoginRequiredSheet({this.reason, this.onAuthed});
  final String? reason;
  final VoidCallback? onAuthed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // If user becomes authenticated while sheet is open, fire callback + close.
    ref.listen<AsyncValue<AuthState>>(authNotifierProvider, (_, next) {
      if (next.valueOrNull is AuthAuthenticated) {
        Navigator.of(context).pop();
        onAuthed?.call();
      }
    });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Illustration — logo badge on orange circle
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MoproTokens.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: MoproLogo(
                  variant: MoproLogoVariant.iconOnly,
                  height: 48,
                  forceDark: false,
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Bu özelliği kullanmak için\ngiriş yapın',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (reason != null) ...[
              const SizedBox(height: 8),
              Text(
                reason!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 28),

            // Login CTA
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/auth/login');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: MoproTokens.primaryLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Giriş Yap',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Register CTA
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/auth/register');
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: MoproTokens.primaryLight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Üye Ol',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: MoproTokens.primaryLight,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Guest dismiss
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Misafir olarak devam et',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
