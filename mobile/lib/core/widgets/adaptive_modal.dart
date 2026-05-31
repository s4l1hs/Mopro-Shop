import 'package:flutter/material.dart';
import 'package:mopro/design/responsive/breakpoint_resolver.dart';
import 'package:mopro/features/auth/widgets/auth_card.dart';

/// Presents [builder]'s content adaptively: a scroll-controlled bottom sheet on
/// mobile (`<600`) and a centered dialog on `>=600`, matching the login
/// presenter (§3). The content is presenter-agnostic — the same form widget is
/// reused in both shapes. Returns the value the content pops with (e.g. `true`
/// on a successful submit).
Future<T?> showAdaptiveModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (context.isMobile) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        // Lift the sheet above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: builder(ctx),
          ),
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: AuthCard(child: builder(ctx)),
    ),
  );
}
