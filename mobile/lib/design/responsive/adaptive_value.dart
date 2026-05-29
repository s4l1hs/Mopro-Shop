import 'package:flutter/widgets.dart';
import 'package:mopro/design/responsive/breakpoint_resolver.dart';

/// Typed value that resolves per breakpoint. Use for column counts,
/// paddings, font scales — keeps magic numbers out of widgets.
///
/// Fallback chain: desktop ?? tablet ?? mobile, tablet ?? mobile.
class AdaptiveValue<T> {
  const AdaptiveValue({required this.mobile, this.tablet, this.desktop});
  final T mobile;
  final T? tablet;
  final T? desktop;

  T resolve(BuildContext c) {
    if (c.isDesktop) return desktop ?? tablet ?? mobile;
    if (c.isTablet) return tablet ?? mobile;
    return mobile;
  }
}
