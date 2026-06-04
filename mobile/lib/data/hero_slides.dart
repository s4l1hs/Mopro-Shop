import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class HeroSlide {
  const HeroSlide({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.startColor,
    required this.endColor,
  });

  final String title;
  final String subtitle;
  final String route;
  final Color startColor;
  final Color endColor;
}

/// Home hero-carousel slides. Built at call time (not a `const` list) so the
/// copy can be localised with a literal `.tr()` per field — a `slide.title.tr()`
/// at the render site would be flagged unresolved by the i18n usage analyzer.
List<HeroSlide> heroSlides() => [
      HeroSlide(
        title: 'marketing.hero.cashback_title'.tr(),
        subtitle: 'marketing.hero.cashback_sub'.tr(),
        route: '/',
        startColor: const Color(0xFFCA4E00),
        endColor: const Color(0xFF8B2500),
      ),
      HeroSlide(
        title: 'marketing.hero.secure_title'.tr(),
        subtitle: 'marketing.hero.secure_sub'.tr(),
        route: '/categories',
        startColor: const Color(0xFF1565C0),
        endColor: const Color(0xFF0D47A1),
      ),
      HeroSlide(
        title: 'marketing.hero.shipping_title'.tr(),
        subtitle: 'marketing.hero.shipping_sub'.tr(),
        route: '/categories',
        startColor: const Color(0xFF2E7D32),
        endColor: const Color(0xFF1B5E20),
      ),
      HeroSlide(
        title: 'marketing.hero.season_title'.tr(),
        subtitle: 'marketing.hero.season_sub'.tr(),
        route: '/categories',
        startColor: const Color(0xFF6A1B9A),
        endColor: const Color(0xFF4A148C),
      ),
    ];
