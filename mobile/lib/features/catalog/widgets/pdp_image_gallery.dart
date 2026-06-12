import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Mobile PDP gallery: full-bleed PageView with a bottom thumbnail strip
/// (PD-06 — tap a thumb to jump; the active thumb is highlighted and tracks
/// swipes). Desktop uses `PdpImagePager`, which has its own thumbnail strip.
class PdpImageGallery extends StatefulWidget {
  const PdpImageGallery({
    required this.imageUrls,
    required this.heroTag,
    super.key,
  });

  final List<String> imageUrls;
  final String heroTag;

  @override
  State<PdpImageGallery> createState() => _PdpImageGalleryState();
}

class _PdpImageGalleryState extends State<PdpImageGallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Keep the active thumbnail in sync with swipes.
    _controller.addListener(() {
      final page = _controller.page?.round() ?? 0;
      if (page != _index && mounted) setState(() => _index = page);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;

    if (urls.isEmpty) {
      return ColoredBox(
        color: Colors.grey.shade900,
        child: const Center(
          child: Icon(Icons.image_outlined, size: 80, color: Colors.white24),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: urls.length,
          itemBuilder: (_, i) {
            final img = CachedNetworkImage(
              imageUrl: urls[i],
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorWidget: (_, __, ___) => ColoredBox(
                color: Colors.grey.shade900,
                child: const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 80,
                    color: Colors.white24,
                  ),
                ),
              ),
            );

            final tappable = GestureDetector(
              onTap: () => _openFullscreen(context, i),
              child: img,
            );

            return i == 0
                ? Hero(tag: widget.heroTag, child: tappable)
                : tappable;
          },
        ),
        // PD-06: thumbnail strip (replaces the former worm-dot indicator) —
        // tap to jump, active thumb highlighted, synced with swipes.
        if (urls.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 52,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (var i = 0; i < urls.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _controller.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          ),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color:
                                    i == _index ? Colors.white : Colors.white38,
                                width: i == _index ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CachedNetworkImage(
                              imageUrl: urls[i],
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  ColoredBox(color: Colors.grey.shade800),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openFullscreen(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenGallery(
          imageUrls: widget.imageUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

class _FullscreenGallery extends StatelessWidget {
  const _FullscreenGallery({
    required this.imageUrls,
    required this.initialIndex,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PhotoViewGallery.builder(
        itemCount: imageUrls.length,
        pageController: PageController(initialPage: initialIndex),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        builder: (_, i) => PhotoViewGalleryPageOptions(
          imageProvider: NetworkImage(imageUrls[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 2,
        ),
      ),
    );
  }
}
