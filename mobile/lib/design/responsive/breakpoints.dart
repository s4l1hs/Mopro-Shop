/// Three-tier breakpoint system.
///
///   <600         → mobile
///   600–1024     → tablet
///   ≥1024        → desktop
///
/// Centered content on desktop is clamped to [Breakpoints.desktopContentMax].
enum Breakpoint { mobile, tablet, desktop }

class Breakpoints {
  Breakpoints._();

  static const double mobileMax = 600;
  static const double tabletMax = 1024;

  /// Maximum width of the centered content column on desktop.
  static const double desktopContentMax = 1240;

  /// Horizontal padding applied by [CenteredContentColumn] per breakpoint.
  static const double paddingMobile = 16;
  static const double paddingTablet = 24;
  static const double paddingDesktop = 32;
}
