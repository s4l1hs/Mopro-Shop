import 'package:flutter/widgets.dart';
import 'package:mopro/design/responsive/breakpoint_resolver.dart';
import 'package:mopro/design/responsive/breakpoints.dart';

/// Wraps a screen body so that on desktop it is centered, clamped to
/// [Breakpoints.desktopContentMax], with symmetric horizontal padding
/// that scales per breakpoint (16 mobile / 24 tablet / 32 desktop).
class CenteredContentColumn extends StatelessWidget {
  const CenteredContentColumn({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = context.isDesktop
        ? Breakpoints.paddingDesktop
        : context.isTablet
            ? Breakpoints.paddingTablet
            : Breakpoints.paddingMobile;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: Breakpoints.desktopContentMax,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: child,
        ),
      ),
    );
  }
}
