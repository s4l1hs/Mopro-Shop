import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/responsive/breakpoint_resolver.dart';
import 'package:mopro/features/auth/widgets/auth_card.dart';
import 'package:mopro/features/auth/widgets/login_required.dart';

/// Presents the "login required" prompt adaptively: a bottom sheet on mobile
/// (`<600`) and a centered [AuthCard] dialog on `>=600` (§3). [onAuthed] is the
/// resume callback wired to [LoginRequired.onResume]; [reason] is a short hint.
Future<void> showLoginRequiredSheet(
  BuildContext context, {
  String? reason,
  VoidCallback? onAuthed,
}) {
  if (context.isMobile) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: LoginRequired(reason: reason, onResume: onAuthed),
        ),
      ),
    );
  }
  // Desktop/tablet: centered dialog. showDialog traps focus, closes on Escape
  // and on barrier tap, and restores focus to the trigger on dismiss (§3.4).
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: AuthCard(
        child: LoginRequired(reason: reason, onResume: onAuthed),
      ),
    ),
  );
}

/// If authenticated, runs [onAuthed] immediately; otherwise presents the
/// adaptive login prompt and runs [onAuthed] once the user authenticates.
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
