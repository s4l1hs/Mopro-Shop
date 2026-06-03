import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/core/widgets/mopro_logo.dart';
import 'package:mopro/design/tokens.dart';

/// Wraps any auth form in a responsive shell.
/// - Narrow (<720 px): single column with logo top.
/// - Wide (≥720 px): two-column split — brand panel left, form right.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    required this.child, super.key,
    this.showBackButton = false,
  });

  final Widget child;
  final bool showBackButton;

  static const _breakpoint = 720.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= _breakpoint) {
      return _WideLayout(showBackButton: showBackButton, child: child);
    }
    return _NarrowLayout(showBackButton: showBackButton, child: child);
  }
}

// ── Narrow (mobile) ──────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({required this.child, required this.showBackButton});
  final Widget child;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showBackButton)
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      )
                    else
                      const Center(
                        child: MoproLogo(
                          variant: MoproLogoVariant.fullBrand,
                          height: 72,
                        ),
                      ),
                    const SizedBox(height: 32),
                    child,
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Wide (web / desktop) ────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.child, required this.showBackButton});
  final Widget child;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 55,
            child: _BrandPanel(),
          ),
          Expanded(
            flex: 45,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 48,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showBackButton)
                          IconButton(
                            onPressed: () =>
                                Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back),
                            padding: EdgeInsets.zero,
                          ),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Brand panel ──────────────────────────────────────────────────────

class _BrandPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Built at render time (not a `static const`) so each value prop's copy can
    // be localised per item with its own literal key; a dynamically-indexed key
    // would be flagged unresolved by the i18n usage analyzer.
    final valueProps = <(IconData, String)>[
      (Icons.local_shipping_outlined, 'auth.layout.value_prop_shipping'.tr()),
      (Icons.currency_exchange_outlined, 'auth.layout.value_prop_cashback'.tr()),
      (Icons.verified_user_outlined, 'auth.layout.value_prop_secure'.tr()),
    ];
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MoproTokens.primaryLight, Color(0xFFE05800)],
        ),
      ),
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // White-background logo in a white card on orange → clean badge look
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(40),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const MoproLogo(
              variant: MoproLogoVariant.fullBrand,
              height: 80,
              forceDark: false,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'auth.layout.headline'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 32),
          ...valueProps.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(51),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.$1, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    item.$2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
