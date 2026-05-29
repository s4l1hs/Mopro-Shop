import 'package:flutter/material.dart';
import 'package:mopro/core/widgets/mopro_logo.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';

/// Minimal placeholder so §3 (adaptive AppShell) compiles. §4 replaces
/// the body with a real Trendyol-style header (logo + search pill +
/// favorites / cart / account region with badges).
class WebHeader extends StatelessWidget implements PreferredSizeWidget {
  const WebHeader({super.key});

  static const double _desktopHeight = 64;
  static const double _tabletHeight = 56;

  @override
  Size get preferredSize => const Size.fromHeight(_desktopHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark
        ? MoproTokens.borderDark
        : MoproTokens.borderLight;
    final height = context.isDesktop ? _desktopHeight : _tabletHeight;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: const [
              MoproLogo(variant: MoproLogoVariant.withText, height: 32),
              Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
