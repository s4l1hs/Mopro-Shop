import 'package:flutter/widgets.dart';
import 'package:mopro/design/responsive/breakpoints.dart';

/// Pure breakpoint resolution. Boundary semantics:
///   width <  600   → mobile
///   600 ≤ width < 1024 → tablet
///   width ≥ 1024   → desktop
class BreakpointResolver {
  const BreakpointResolver._();

  static Breakpoint resolve(double width) {
    if (width < Breakpoints.mobileMax) return Breakpoint.mobile;
    if (width < Breakpoints.tabletMax) return Breakpoint.tablet;
    return Breakpoint.desktop;
  }
}

/// Convenience accessors backed by `MediaQuery.sizeOf(context).width`.
/// Note: inside a [ResponsiveBuilder] subtree you should resolve from
/// `BoxConstraints.maxWidth` instead so embedded panels react to their
/// parent column rather than the window.
extension BreakpointContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  Breakpoint get bp => BreakpointResolver.resolve(screenWidth);
  bool get isMobile => bp == Breakpoint.mobile;
  bool get isTablet => bp == Breakpoint.tablet;
  bool get isDesktop => bp == Breakpoint.desktop;
}
