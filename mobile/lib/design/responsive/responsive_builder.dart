import 'package:flutter/widgets.dart';
import 'package:mopro/design/responsive/breakpoint_resolver.dart';
import 'package:mopro/design/responsive/breakpoints.dart';

/// Builds different children per breakpoint based on the *parent's*
/// constraints (not the window size). This lets an embedded panel
/// resolve as "mobile" even on a desktop window — useful for the
/// Cart's right sidebar or the Account two-pane shell.
///
/// [mobile] is required. [tablet] falls back to [mobile]; [desktop]
/// falls back to [tablet] then [mobile].
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    required this.mobile,
    this.tablet,
    this.desktop,
    super.key,
  });

  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final bp = BreakpointResolver.resolve(constraints.maxWidth);
        switch (bp) {
          case Breakpoint.desktop:
            return (desktop ?? tablet ?? mobile)(ctx);
          case Breakpoint.tablet:
            return (tablet ?? mobile)(ctx);
          case Breakpoint.mobile:
            return mobile(ctx);
        }
      },
    );
  }
}
