import 'package:flutter/material.dart';

/// Native, opaque background colour baked into each brand-locked image.
///
/// A brand-locked asset is multi-colour and must render exactly as authored, so
/// it needs a surrounding surface that matches its baked-in background under any
/// theme. `BrandLockedImage` reads this registry by asset path to paint that
/// surface.
///
/// Currently empty by design: the only brand-locked assets in the app are the
/// Mopro logo variants, and those are owned by `MoproLogo`, which variant-selects
/// a white/black asset and supplies its own matching surface (the documented
/// §2.3 exception — see `mobile/assets/images/MANIFEST.md`). Any *new*
/// brand-locked, non-logo image gets an entry here, e.g.:
///
/// ```dart
/// 'assets/images/payment_methods.png': Color(0xFFEEEEEE),
/// ```
const Map<String, Color> brandLockedBackgrounds = <String, Color>{};
