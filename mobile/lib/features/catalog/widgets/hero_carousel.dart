import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/data/hero_slides.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key});

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final _controller = PageController();
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final next = (_current + 1) % heroSlides.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: heroSlides.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => _HeroSlideWidget(slide: heroSlides[i]),
          ),
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: SmoothPageIndicator(
                controller: _controller,
                count: heroSlides.length,
                effect: const WormEffect(
                  dotWidth: 8,
                  dotHeight: 8,
                  activeDotColor: Colors.white,
                  dotColor: Colors.white54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSlideWidget extends StatelessWidget {
  const _HeroSlideWidget({required this.slide});

  final HeroSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => context.push(slide.route),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [slide.startColor, slide.endColor],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              slide.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              slide.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withAlpha(180),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
