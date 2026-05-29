import 'package:flutter/material.dart';
import 'package:mopro/core/widgets/mopro_logo.dart';

/// Centered card wrapper for auth content presented as a dialog on >=600 widths
/// (login-required, and future auth modals). 480dp width clamp, surface
/// background, 1dp outlineVariant border, 12dp corners, 24dp padding, MoproLogo
/// top-center, then [child].
class AuthCard extends StatelessWidget {
  const AuthCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MoproLogo(height: 28),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
