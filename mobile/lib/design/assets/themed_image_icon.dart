import 'package:flutter/material.dart';

/// Renders a single-colour ("theme-adaptive") asset PNG as a theme-tinted icon.
///
/// Wraps [ImageIcon] so the asset inherits `IconTheme.of(context).color` (unless
/// [color] is given), exactly like a Material font icon — it flips with
/// light/dark instead of being baked to one colour. Use this for transparent,
/// one-hue PNGs.
///
/// Multi-colour, brand-locked images must NOT use this (tinting would flatten
/// them) — see `BrandLockedImage`.
class ThemedImageIcon extends StatelessWidget {
  const ThemedImageIcon(
    this.path, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });

  /// Asset path, e.g. `assets/images/foo.png`.
  final String path;

  /// Rendered square size in logical pixels.
  final double size;

  /// Tint override; defaults to the ambient `IconTheme.of(context).color`.
  final Color? color;

  /// Optional semantic label for screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return ImageIcon(
      AssetImage(path),
      size: size,
      color: color ?? IconTheme.of(context).color,
      semanticLabel: semanticLabel,
    );
  }
}
