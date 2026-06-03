import 'package:flutter/material.dart';

/// Color and spacing constants derived from globals.css OKLCH tokens.
/// OKLCH values converted to sRGB hex for Flutter.
abstract final class MoproTokens {
  MoproTokens._();

  // ── Primary — Mopro orange ──────────────────────────────────────────────────
  /// oklch(0.58 0.18 47) ≈ #CA4E00 — WCAG AA 4.56:1 on white
  static const Color primaryLight = Color(0xFFCA4E00);
  /// oklch(0.72 0.17 47) ≈ #E36925 — bright orange on dark backgrounds
  static const Color primaryDark = Color(0xFFE97230);
  static const Color onPrimaryLight = Color(0xFFFFFFFF);
  /// oklch(0.14 0.005 50) — near-black for dark-mode primary text
  static const Color onPrimaryDark = Color(0xFF231E18);

  // ── Surfaces ────────────────────────────────────────────────────────────────
  /// oklch(1 0 0)
  static const Color backgroundLight = Color(0xFFFFFFFF);
  /// oklch(0.16 0.005 50)
  static const Color backgroundDark = Color(0xFF26211C);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  /// oklch(0.20 0.005 50)
  static const Color surfaceDark = Color(0xFF302A24);
  /// oklch(0.965 0.005 50)
  static const Color surfaceVariantLight = Color(0xFFF5F4F3);
  /// oklch(0.26 0.005 50)
  static const Color surfaceVariantDark = Color(0xFF3E3731);

  // ── Foreground / text ───────────────────────────────────────────────────────
  /// oklch(0.18 0.005 50)
  static const Color foregroundLight = Color(0xFF2B2520);
  /// oklch(0.96 0.003 50)
  static const Color foregroundDark = Color(0xFFF5F2EF);
  /// oklch(0.50 0.01 50)
  static const Color mutedFgLight = Color(0xFF776E65);
  /// oklch(0.70 0.01 50)
  static const Color mutedFgDark = Color(0xFFB8AFA7);

  // ── Semantic ────────────────────────────────────────────────────────────────
  /// oklch(0.62 0.22 27) — action red for discount badges / destructive
  static const Color destructiveLight = Color(0xFFC4400D);
  /// oklch(0.68 0.22 27)
  static const Color destructiveDark = Color(0xFFDB541E);
  /// oklch(0.62 0.18 145) — success green
  static const Color successLight = Color(0xFF2F7B3A);
  /// oklch(0.70 0.18 145)
  static const Color successDark = Color(0xFF4CAF58);
  /// oklch(0.78 0.15 75) — warning amber
  static const Color warningLight = Color(0xFFB87A00);
  /// oklch(0.82 0.15 75)
  static const Color warningDark = Color(0xFFCB9A00);
  /// Rating-star gold. Shared by every rating-star glyph (product card, PDP
  /// header, review rows, histogram) so the app never drifts between gold and
  /// brand-orange for the same concept. Theme-independent by design.
  static const Color ratingStar = Color(0xFFFFB400);

  // ── Borders ─────────────────────────────────────────────────────────────────
  /// oklch(0.92 0.003 50)
  static const Color borderLight = Color(0xFFEAE7E3);
  /// oklch(0.30 0.005 50)
  static const Color borderDark = Color(0xFF4A423A);

  // ── Spacing grid (8-pt base) ────────────────────────────────────────────────
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;
  static const double space48 = 48;

  // ── Border radius ───────────────────────────────────────────────────────────
  static const double radiusSm = 6; // 0.375rem
  static const double radiusMd = 8; // 0.5rem
  static const double radiusLg = 12; // 0.75rem
  static const double radiusXl = 16; // 1rem
  static const double radius2xl = 24; // 1.5rem
  static const double radiusFull = 999;
}
