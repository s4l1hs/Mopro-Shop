import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

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
        if (urls.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: SmoothPageIndicator(
                controller: _controller,
                count: urls.length,
                effect: const WormEffect(
                  dotWidth: 7,
                  dotHeight: 7,
                  activeDotColor: Colors.white,
                  dotColor: Colors.white54,
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
