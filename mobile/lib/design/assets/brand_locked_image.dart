import 'package:flutter/material.dart';
import 'package:mopro/design/assets/brand_locked_backgrounds.dart';

/// Renders a brand-locked (multi-colour, fixed-surface) image on its documented
/// background colour, so the asset's baked-in background always sits on a
/// matching field regardless of the active theme.
///
/// The colour is looked up from [brandLockedBackgrounds] by [path]; pass
/// [background] to override (and to make the widget usable/testable before a
/// path is registered). In debug, an unregistered path with no override trips
/// an assert; in release it falls back to transparent.
class BrandLockedImage extends StatelessWidget {
  const BrandLockedImage(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.background,
  });

  /// Asset path, e.g. `assets/images/foo.png`.
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Surface colour override; defaults to the [brandLockedBackgrounds] entry.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? brandLockedBackgrounds[path];
    assert(
      bg != null,
      'BrandLockedImage: no background registered for "$path" in '
      'brandLockedBackgrounds, and none passed explicitly.',
    );
    return Container(
      width: width,
      height: height,
      color: bg ?? Colors.transparent,
      child: Image.asset(path, width: width, height: height, fit: fit),
    );
  }
}
