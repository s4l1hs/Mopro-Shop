import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/features/catalog/providers/home_provider.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/widgets/home_category_grid.dart';
import 'package:mopro/features/catalog/widgets/product_rail.dart';
import 'package:mopro/features/catalog/widgets/trust_bar.dart';
import 'package:mopro/features/home/providers/home_wallet_summary_provider.dart';
import 'package:mopro/features/wallet/widgets/coin_balance_pill.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class CatalogHomeScreen extends ConsumerWidget {
  const CatalogHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final railsAsync = ref.watch(homeRailsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(homeBannersProvider)
            ..invalidate(homeRailsProvider)
            ..invalidate(productsRailProvider('recommended'))
            ..invalidate(productsRailProvider('bestseller'))
            ..invalidate(productsRailProvider('newest'));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Search pill (Trendyol-style top bar) ─────────────────────────
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: _HomeTopBar(),
              ),
            ),

            // ── Banner carousel (server-driven) ──────────────────────────────
            const SliverToBoxAdapter(child: _BannerCarousel()),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // ── Category puck grid ────────────────────────────────────────────
            const SliverToBoxAdapter(child: HomeCategoryGrid()),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // ── Trust bar ─────────────────────────────────────────────────────
            const SliverToBoxAdapter(child: TrustBar()),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),

            // ── Server-driven product rails ───────────────────────────────────
            ...railsAsync.when(
              loading: () => [
                SliverToBoxAdapter(
                  child: ProductRail(
                    title: 'home.section_recommended'.tr(),
                    sort: 'recommended',
                    seeAllRoute: '/categories',
                  ),
                ),
              ],
              error: (_, __) => [],
              data: (rails) => rails
                  .map((rail) => SliverToBoxAdapter(
                        child: ProductRail(
                          title: rail.title,
                          sort: rail.key,
                          seeAllRoute: '/categories',
                        ),
                      ))
                  .toList(),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

// ── Top bar (search pill + coin pill) ────────────────────────────────────────

class _HomeTopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider).valueOrNull;
    final isAuthed = authState is AuthAuthenticated;

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          // Animated search pill
          Expanded(child: _AnimatedSearchPill()),
          if (isAuthed) ...[
            const SizedBox(width: 8),
            const _CoinBalanceAction(),
          ],
        ],
      ),
    );
  }
}

class _AnimatedSearchPill extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AnimatedSearchPill> createState() =>
      _AnimatedSearchPillState();
}

class _AnimatedSearchPillState extends ConsumerState<_AnimatedSearchPill> {
  int _index = 0;
  Timer? _timer;
  final List<String> _defaultHints = const [
    'Ürün, kategori veya marka ara',
    'Akıllı telefon ara',
    'Giyim ara',
    'Spor ayakkabı ara',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _hints.length);
    });
  }

  List<String> get _hints {
    final trending =
        ref.read(trendingSearchesProvider).valueOrNull ?? _defaultHints;
    return trending.isNotEmpty ? trending : _defaultHints;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFF2F2F2);

    return GestureDetector(
      onTap: () => context.push('/search'),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  _hints.isEmpty ? _defaultHints[0] : _hints[_index % _hints.length],
                  key: ValueKey(_index),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Icon(
              Icons.mic_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinBalanceAction extends ConsumerWidget {
  const _CoinBalanceAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(homeWalletSummaryProvider);
    return summaryAsync.maybeWhen(
      data: (balance) => CoinBalancePill(
        amountMinor: balance.amountMinor,
        currency: balance.currency,
        onTap: () => context.push('/wallet'),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ── Server-driven banner carousel ────────────────────────────────────────────

class _BannerCarousel extends ConsumerStatefulWidget {
  const _BannerCarousel();

  @override
  ConsumerState<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends ConsumerState<_BannerCarousel> {
  final _ctrl = PageController();
  int _page = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final banners =
          ref.read(homeBannersProvider).valueOrNull ?? const [];
      if (banners.isEmpty) return;
      final next = (_page + 1) % banners.length;
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(homeBannersProvider);

    return bannersAsync.when(
      loading: () => const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(color: Color(0xFFEEEEEE)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (banners) {
        if (banners.isEmpty) return const SizedBox.shrink();
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              PageView.builder(
                controller: _ctrl,
                itemCount: banners.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (ctx, i) {
                  final b = banners[i];
                  return GestureDetector(
                    onTap: () => context.go(b.deepLink),
                    child: CachedNetworkImage(
                      imageUrl: b.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const ColoredBox(
                        color: Color(0xFFEEEEEE),
                      ),
                      errorWidget: (_, __, ___) => const ColoredBox(
                        color: Color(0xFFEEEEEE),
                      ),
                    ),
                  );
                },
              ),
              // Dot indicator
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedSmoothIndicator(
                    activeIndex: _page,
                    count: banners.length,
                    effect: WormEffect(
                      dotWidth: 7,
                      dotHeight: 7,
                      activeDotColor: Colors.white,
                      dotColor: Colors.white.withAlpha(128),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
