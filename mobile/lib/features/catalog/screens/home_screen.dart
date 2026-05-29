import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/catalog/providers/home_provider.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/widgets/home_category_grid.dart';
import 'package:mopro/features/catalog/widgets/home_footer.dart';
import 'package:mopro/features/catalog/widgets/mood_stories_strip.dart';
import 'package:mopro/features/catalog/widgets/product_rail.dart';
import 'package:mopro/features/catalog/widgets/trust_bar.dart';
import 'package:mopro/features/home/providers/flash_deals_provider.dart';
// ignore: lines_longer_than_80_chars
import 'package:mopro/features/home/providers/home_wallet_summary_provider.dart';
import 'package:mopro/features/home/widgets/flash_deals_rail.dart';
import 'package:mopro/features/wallet/widgets/coin_balance_pill.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class CatalogHomeScreen extends ConsumerWidget {
  const CatalogHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // §6.3: hint the server how many rails to surface (desktop ≤6, mobile ≤3).
    final railsLayout = context.isDesktop ? 'desktop' : 'mobile';
    final railsAsync = ref.watch(homeRailsProvider(railsLayout));

    // Adaptive composition (§2). Mobile is unchanged: full-width, scroller
    // rails. Tablet/desktop center content in a CenteredContentColumn and
    // render rails as grids.
    final isMobile = context.isMobile;
    final railLayout = isMobile ? RailLayout.scroller : RailLayout.grid;
    final gridColumns = context.isDesktop ? 5 : 3;
    final maxItems = context.isDesktop ? 10 : 6;

    // Center + clamp + pad non-mobile sections; pass through on mobile so the
    // existing mobile composition (and its goldens) are untouched.
    Widget wrap(Widget child) =>
        isMobile ? child : CenteredContentColumn(child: child);

    ProductRail rail(String title, String sort) => ProductRail(
          title: title,
          sort: sort,
          seeAllRoute: '/categories',
          layout: railLayout,
          gridColumns: gridColumns,
          maxItems: maxItems,
        );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(homeBannersProvider)
            ..invalidate(homeMoodStoriesProvider)
            ..invalidate(homeRailsProvider(railsLayout))
            ..invalidate(flashDealsProvider)
            ..invalidate(productsRailProvider('recommended'))
            ..invalidate(productsRailProvider('bestseller'))
            ..invalidate(productsRailProvider('newest'));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Search pill (Trendyol-style top bar) ─────────────────────────
            SliverToBoxAdapter(
              child: SafeArea(bottom: false, child: _HomeTopBar()),
            ),

            // ── Mood stories strip (server-driven) ────────────────────────────
            SliverToBoxAdapter(child: wrap(const MoodStoriesStrip())),

            // ── Banner carousel (server-driven) ──────────────────────────────
            SliverToBoxAdapter(
              child: wrap(_BannerCarousel(desktop: context.isDesktop)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // ── Flash deals (additive; renders nothing when no active deal) ──
            SliverToBoxAdapter(child: wrap(const FlashDealsRail())),

            // ── Category puck grid ─────────────────────────────────────
            SliverToBoxAdapter(child: wrap(const HomeCategoryGrid())),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // ── Trust bar ──────────────────────────────────────────────
            SliverToBoxAdapter(child: wrap(const TrustBar())),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),

            // ── Server-driven product rails ────────────────────────────
            ...railsAsync.when(
              loading: () => [
                SliverToBoxAdapter(
                  child: wrap(rail('home.section_recommended'.tr(), 'recommended')),
                ),
              ],
              error: (_, __) => const [],
              data: (rails) => rails
                  .map((r) => SliverToBoxAdapter(child: wrap(rail(r.title, r.key))))
                  .toList(),
            ),

            // ── Desktop-only "Editor's picks / Recently viewed" sub-section ──
            // Two 50% columns, 32dp gap. Recently-viewed has no local-history
            // provider yet, so it is always empty and hidden — the row collapses
            // to a single full-width Editor's picks column (§6.1).
            if (context.isDesktop)
              const SliverToBoxAdapter(child: _EditorsPicksSection()),

            // ── Desktop-only thin footer ───────────────────────────────
            if (context.isDesktop)
              const SliverToBoxAdapter(child: HomeFooter()),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

/// Desktop-only "Editor's picks" sub-section: a 3×2 product grid inside the
/// centered content column. The companion "Recently viewed" column is omitted
/// while there is no local recently-viewed history provider (hide-when-empty,
/// §6.1) — the row is therefore single-column / full-width.
class _EditorsPicksSection extends StatelessWidget {
  const _EditorsPicksSection();

  @override
  Widget build(BuildContext context) {
    return CenteredContentColumn(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ProductRail(
          title: 'home.editors_picks'.tr(),
          sort: 'bestseller',
          layout: RailLayout.grid,
          maxItems: 6,
        ),
      ),
    );
  }
}

// ── Top bar (search pill + coin pill) ──────────────────────────────────

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
                  _hints.isEmpty
                      ? _defaultHints[0]
                      : _hints[_index % _hints.length],
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

// ── Server-driven banner carousel ──────────────────────────────────────

class _BannerCarousel extends ConsumerStatefulWidget {
  const _BannerCarousel({this.desktop = false});

  /// Desktop renders a wider 16:5 banner with prev/next chevrons and
  /// pauses autoplay while hovered.
  final bool desktop;

  @override
  ConsumerState<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends ConsumerState<_BannerCarousel> {
  final _ctrl = PageController();
  int _page = 0;
  Timer? _timer;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _paused) return;
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
    final aspect = widget.desktop ? 16 / 5 : 16 / 9;

    return bannersAsync.when(
      loading: () => AspectRatio(
        aspectRatio: aspect,
        child: const ColoredBox(color: Color(0xFFEEEEEE)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (banners) {
        if (banners.isEmpty) return const SizedBox.shrink();
        final carousel = AspectRatio(
          aspectRatio: aspect,
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
              // Desktop prev/next chevrons.
              if (widget.desktop) ..._chevrons(banners.length),
            ],
          ),
        );
        if (!widget.desktop) return carousel;
        // Desktop: pause autoplay while hovered.
        return MouseRegion(
          onEnter: (_) => _paused = true,
          onExit: (_) => _paused = false,
          child: carousel,
        );
      },
    );
  }

  List<Widget> _chevrons(int count) {
    void go(int delta) {
      if (count == 0) return;
      final next = (_page + delta) % count;
      _ctrl.animateToPage(
        next < 0 ? next + count : next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }

    Widget chevron(IconData icon, VoidCallback onTap, Alignment align) =>
        Align(
          alignment: align,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Material(
              color: Colors.black.withAlpha(64),
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(icon, color: Colors.white),
                onPressed: onTap,
              ),
            ),
          ),
        );

    return [
      chevron(Icons.chevron_left, () => go(-1), Alignment.centerLeft),
      chevron(Icons.chevron_right, () => go(1), Alignment.centerRight),
    ];
  }
}
