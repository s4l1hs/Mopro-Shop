import 'dart:math';
import 'dart:ui';

/// WCAG 2.1 relative luminance of a color (sRGB → linear).
double relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  // Color.r/.g/.b are normalized sRGB channels (0..1).
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio between two colors (1.0 .. 21.0).
double wcagContrast(Color fg, Color bg) {
  final fgL = relativeLuminance(fg);
  final bgL = relativeLuminance(bg);
  final lighter = max(fgL, bgL);
  final darker = min(fgL, bgL);
  return (lighter + 0.05) / (darker + 0.05);
}
