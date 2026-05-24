import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/tokens.dart';

ThemeData buildLightTheme() => _build(brightness: Brightness.light);
ThemeData buildDarkTheme() => _build(brightness: Brightness.dark);

ThemeData _build({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;

  final primary = isDark ? MoproTokens.primaryDark : MoproTokens.primaryLight;
  final onPrimary =
      isDark ? MoproTokens.onPrimaryDark : MoproTokens.onPrimaryLight;
  final background =
      isDark ? MoproTokens.backgroundDark : MoproTokens.backgroundLight;
  final surface = isDark ? MoproTokens.surfaceDark : MoproTokens.surfaceLight;
  final surfaceVariant = isDark
      ? MoproTokens.surfaceVariantDark
      : MoproTokens.surfaceVariantLight;
  final onSurface =
      isDark ? MoproTokens.foregroundDark : MoproTokens.foregroundLight;
  final onSurfaceVariant =
      isDark ? MoproTokens.mutedFgDark : MoproTokens.mutedFgLight;
  final outline = isDark ? MoproTokens.borderDark : MoproTokens.borderLight;
  final error =
      isDark ? MoproTokens.destructiveDark : MoproTokens.destructiveLight;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primary.withAlpha(isDark ? 51 : 26),
    onPrimaryContainer: primary,
    secondary: surfaceVariant,
    onSecondary: onSurface,
    secondaryContainer: surfaceVariant,
    onSecondaryContainer: onSurface,
    tertiary: isDark ? MoproTokens.successDark : MoproTokens.successLight,
    onTertiary: Colors.white,
    tertiaryContainer:
        (isDark ? MoproTokens.successDark : MoproTokens.successLight)
            .withAlpha(26),
    onTertiaryContainer:
        isDark ? MoproTokens.successDark : MoproTokens.successLight,
    error: error,
    onError: Colors.white,
    errorContainer: error.withAlpha(26),
    onErrorContainer: error,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerHighest: surfaceVariant,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outline,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: onSurface,
    onInverseSurface: surface,
    inversePrimary: isDark ? MoproTokens.primaryLight : MoproTokens.primaryDark,
  );

  final textTheme = GoogleFonts.interTextTheme(
    ThemeData(brightness: brightness).textTheme,
  ).copyWith(
    displayLarge: GoogleFonts.inter(
      fontSize: 57,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
      color: onSurface,
    ),
    displayMedium: GoogleFonts.inter(
      fontSize: 45,
      fontWeight: FontWeight.w400,
      color: onSurface,
    ),
    displaySmall: GoogleFonts.inter(
      fontSize: 36,
      fontWeight: FontWeight.w400,
      color: onSurface,
    ),
    headlineLarge: GoogleFonts.inter(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: onSurface,
    ),
    headlineMedium: GoogleFonts.inter(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: onSurface,
    ),
    headlineSmall: GoogleFonts.inter(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
    titleLarge: GoogleFonts.inter(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
    titleMedium: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      color: onSurface,
    ),
    titleSmall: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: onSurface,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.5,
      color: onSurface,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      color: onSurface,
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      color: onSurfaceVariant,
    ),
    labelLarge: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: onSurface,
    ),
    labelMedium: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: onSurface,
    ),
    labelSmall: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: onSurfaceVariant,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(
      elevation: MoproTokens.space2,
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MoproTokens.radiusLg),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: primary,
      unselectedItemColor: onSurfaceVariant,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: primary.withAlpha(26),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: primary);
        }
        return IconThemeData(color: onSurfaceVariant);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final base = GoogleFonts.inter(fontSize: 12, letterSpacing: 0.5);
        if (states.contains(WidgetState.selected)) {
          return base.copyWith(
            fontWeight: FontWeight.w600,
            color: primary,
          );
        }
        return base.copyWith(
          fontWeight: FontWeight.w400,
          color: onSurfaceVariant,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MoproTokens.radiusMd),
        ),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: outline),
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MoproTokens.radiusMd),
        ),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(64, 40),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceVariant,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MoproTokens.radiusMd),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MoproTokens.radiusMd),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MoproTokens.radiusMd),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MoproTokens.radiusMd),
        borderSide: BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MoproTokens.radiusMd),
        borderSide: BorderSide(color: error, width: 2),
      ),
      hintStyle: GoogleFonts.inter(
        fontSize: 15,
        color: onSurfaceVariant,
        fontWeight: FontWeight.w400,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariant,
      selectedColor: primary.withAlpha(26),
      labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
      side: BorderSide(color: outline),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MoproTokens.radiusFull),
      ),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? MoproTokens.surfaceVariantDark : onSurface,
      contentTextStyle: GoogleFonts.inter(
        fontSize: 14,
        color: isDark ? MoproTokens.foregroundDark : MoproTokens.backgroundLight,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MoproTokens.radiusMd),
      ),
    ),
  );
}
