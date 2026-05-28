import 'package:flutter/material.dart';

enum MoproLogoVariant {
  /// Just the gladiator-bag icon, no text.
  iconOnly,

  /// Icon + "MOPRO" text.
  withText,

  /// Icon + "MOPRO SHOP" text — fullest brand mark.
  fullBrand,
}

/// Displays the correct Mopro brand image based on [variant] and theme.
///
/// - Light mode → "beyaz" (white BG) asset, blends on white/surface.
/// - Dark mode  → "siyah" (black BG) asset wrapped in a black capsule so
///   the #000 image background matches the container exactly.
class MoproLogo extends StatelessWidget {
  const MoproLogo({
    super.key,
    this.variant = MoproLogoVariant.withText,
    this.height = 36,
    this.forceDark,
  });

  final MoproLogoVariant variant;
  final double height;

  /// Override brightness. Useful for brand panels with a fixed background.
  final bool? forceDark;

  @override
  Widget build(BuildContext context) {
    final isDark =
        forceDark ?? Theme.of(context).brightness == Brightness.dark;
    final asset = _asset(isDark);

    if (!isDark) {
      // White-background images blend seamlessly on light surfaces.
      return Image.asset(asset, height: height, fit: BoxFit.contain);
    }

    // Dark mode: wrap in a black rounded container so the image BG is hidden.
    final containerHeight = height * 1.1;
    return Container(
      height: containerHeight,
      padding: EdgeInsets.symmetric(
        horizontal: height * 0.15,
        vertical: height * 0.05,
      ),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(height * 0.18),
      ),
      child: Image.asset(asset, height: height, fit: BoxFit.contain),
    );
  }

  String _asset(bool isDark) {
    if (isDark) {
      return switch (variant) {
        MoproLogoVariant.iconOnly => 'assets/images/Yazısız logo siyah.png',
        MoproLogoVariant.withText =>
          'assets/images/Sadece mopro yazan siyah.png',
        MoproLogoVariant.fullBrand =>
          'assets/images/Mopro shop yazılı siyah.png',
      };
    }
    return switch (variant) {
      MoproLogoVariant.iconOnly => 'assets/images/Yazısız logo beyaz.png',
      MoproLogoVariant.withText =>
        'assets/images/Sadece mopro yazan beyaz.png',
      MoproLogoVariant.fullBrand =>
        'assets/images/Mopro Shop yazılı beyaz.png',
    };
  }
}
