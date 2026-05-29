import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mopro/design/responsive/responsive_image_url.dart';

/// Drop-in replacement for [CachedNetworkImage] that appends a CDN width hint
/// (`?w=`) sized to the box the image will occupy.
///
/// Uses [LayoutBuilder] to read the laid-out logical width and
/// `MediaQuery.devicePixelRatioOf` for DPR, then [responsiveImageUrl] to bucket
/// the physical width. If constraints are horizontally unbounded it falls back
/// to [fallbackWidthLogical]. Same `placeholder`/`errorWidget` builders as
/// `CachedNetworkImage`, so migration is mechanical and the failure behaviour
/// (and the placeholder pattern) is unchanged if the CDN ignores `?w=`.
class ResponsiveNetworkImage extends StatelessWidget {
  const ResponsiveNetworkImage({
    required this.imageUrl,
    super.key,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.fallbackWidthLogical = 400,
  });

  final String imageUrl;
  final BoxFit fit;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  /// Logical width used when the incoming constraints are horizontally
  /// unbounded (e.g. inside a horizontal scroller without a fixed item width).
  final double fallbackWidthLogical;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final logical = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : fallbackWidthLogical;
        final url = responsiveImageUrl(
          imageUrl,
          targetWidthLogical: logical,
          devicePixelRatio: dpr,
        );
        return CachedNetworkImage(
          imageUrl: url,
          fit: fit,
          placeholder: placeholder,
          errorWidget: errorWidget,
        );
      },
    );
  }
}
