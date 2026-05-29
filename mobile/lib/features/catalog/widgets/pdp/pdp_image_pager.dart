import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Desktop/tablet image pager for the PDP gallery: a square main image with a
/// thumbnail strip below and prev/next arrows. When [enableHoverZoom] is true
/// (set by the screen only at >=1024 width AND when the last pointer was a
/// mouse), hovering the main image shows an in-place 2x lens that zooms about
/// the cursor.
///
/// Deviation from the spec (§3.3): the spec asks for a separate 480dp preview
/// pane to the *right* of the image. That pane would overflow into — and
/// visually collide with — the 480dp buy-box column, and routing it through a
/// top-level Overlay to escape the column is brittle. Per the prompt's §12
/// "take a defensible position and document" guidance, we zoom *in place*
/// (clipped to the image bounds) instead. Same information, no collision.
class PdpImagePager extends StatefulWidget {
  const PdpImagePager({
    required this.imageUrls,
    this.onIndexChanged,
    this.enableHoverZoom = false,
    super.key,
  });

  final List<String> imageUrls;
  final void Function(int index)? onIndexChanged;
  final bool enableHoverZoom;

  /// Key of the zoom-lens overlay (present only while hovering with zoom on).
  static const zoomOverlayKey = Key('pdp-hover-zoom');

  @override
  State<PdpImagePager> createState() => _PdpImagePagerState();
}

class _PdpImagePagerState extends State<PdpImagePager> {
  int _index = 0;
  bool _hovering = false;
  Offset _cursor = Offset.zero;
  Size _boxSize = Size.zero;

  void _select(int i) {
    if (i < 0 || i >= widget.imageUrls.length || i == _index) return;
    setState(() => _index = i);
    widget.onIndexChanged?.call(i);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final urls = widget.imageUrls;

    if (urls.isEmpty) {
      return AspectRatio(
        aspectRatio: 1,
        child: ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.image_outlined, size: 80, color: cs.outlineVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _boxSize = constraints.biggest;
              final image = CachedNetworkImage(
                imageUrl: urls[_index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorWidget: (_, __, ___) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 64,
                    color: cs.outlineVariant,
                  ),
                ),
              );

              final stack = Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  if (widget.enableHoverZoom && _hovering)
                    _ZoomLens(
                      key: PdpImagePager.zoomOverlayKey,
                      cursor: _cursor,
                      box: _boxSize,
                      child: image,
                    ),
                  if (urls.length > 1) ..._arrows(),
                ],
              );

              if (!widget.enableHoverZoom) return stack;
              return MouseRegion(
                onEnter: (_) => setState(() => _hovering = true),
                onExit: (_) => setState(() => _hovering = false),
                onHover: (e) => setState(() => _cursor = e.localPosition),
                child: stack,
              );
            },
          ),
        ),
        if (urls.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _select(i),
                child: Container(
                  width: 64,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: i == _index ? cs.primary : cs.outlineVariant,
                      width: i == _index ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CachedNetworkImage(
                    imageUrl: urls[i],
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        ColoredBox(color: cs.surfaceContainerHighest),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _arrows() {
    Widget arrow(IconData icon, int delta, Alignment align) => Align(
          alignment: align,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Material(
              color: Colors.black.withAlpha(64),
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(icon, color: Colors.white),
                onPressed: () => _select(_index + delta),
              ),
            ),
          ),
        );
    return [
      arrow(Icons.chevron_left, -1, Alignment.centerLeft),
      arrow(Icons.chevron_right, 1, Alignment.centerRight),
    ];
  }
}

/// In-place 2x zoom lens that scales the image about the cursor, clipped to the
/// image bounds.
class _ZoomLens extends StatelessWidget {
  const _ZoomLens({
    required this.child,
    required this.cursor,
    required this.box,
    super.key,
  });

  final Widget child;
  final Offset cursor;
  final Size box;

  @override
  Widget build(BuildContext context) {
    // Map the cursor to a [-1, 1] alignment so Transform.scale zooms about it
    // (the image point under the cursor stays fixed). Avoids Matrix4 directly.
    final ax = box.width == 0
        ? 0.0
        : (cursor.dx.clamp(0.0, box.width) / box.width) * 2 - 1;
    final ay = box.height == 0
        ? 0.0
        : (cursor.dy.clamp(0.0, box.height) / box.height) * 2 - 1;
    return ClipRect(
      child: Transform.scale(
        scale: 2,
        alignment: Alignment(ax, ay),
        child: child,
      ),
    );
  }
}
