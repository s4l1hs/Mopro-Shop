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

const heroSlides = <HeroSlide>[
  HeroSlide(
    title: 'Süresiz Cashback',
    subtitle: 'Her alışverişten aylık Mopro Coin kazan — sonsuza dek.',
    route: '/',
    startColor: Color(0xFFCA4E00),
    endColor: Color(0xFF8B2500),
  ),
  HeroSlide(
    title: 'Güvenli Alışveriş',
    subtitle: '3D güvenli ödeme ve kolay iade güvencesiyle alışveriş yapın.',
    route: '/categories',
    startColor: Color(0xFF1565C0),
    endColor: Color(0xFF0D47A1),
  ),
  HeroSlide(
    title: 'Ücretsiz Kargo',
    subtitle: 'Tüm siparişlerinizde ücretsiz kargo fırsatından yararlanın.',
    route: '/categories',
    startColor: Color(0xFF2E7D32),
    endColor: Color(0xFF1B5E20),
  ),
  HeroSlide(
    title: 'Yeni Sezon',
    subtitle: 'En yeni ürünleri keşfedin, cashback kazanmaya başlayın.',
    route: '/categories',
    startColor: Color(0xFF6A1B9A),
    endColor: Color(0xFF4A148C),
  ),
];
