import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro_api/mopro_api.dart';

/// How a [ProductRail] lays out its products.
enum RailLayout {
  /// Native touch scroller (mobile, <600dp). Compact 152×258 cards.
  scroller,

  /// Horizontal carousel (tablet/desktop). Full set, lazy `ListView.builder`;
  /// on desktop (pointer), left/right hover chevrons drive manual sliding.
  /// Replaces the former fixed-column grid (Sprint B).
  carousel,
}

class ProductRail extends ConsumerWidget {
  const ProductRail({
    required this.title,
    required this.sort,
    this.seeAllRoute,
    this.layout = RailLayout.scroller,
    this.maxItems,
    super.key,
  });

  final String title;
  final String sort;
  final String? seeAllRoute;

  /// Scroller (mobile) or carousel (tablet/desktop). The parent picks by
  /// breakpoint.
  final RailLayout layout;

  /// Upper bound on items shown (e.g. 10 on desktop). Not a hard visual cap —
  /// the carousel scrolls through the full set up to this bound.
  final int? maxItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(productsRailProvider(sort));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (seeAllRoute != null)
                TextButton(
                  onPressed: () => context.push(seeAllRoute!),
                  child: Text('home.see_all'.tr()),
                ),
            ],
          ),
        ),
        async.when(
          loading: () => layout == RailLayout.carousel
              ? const _SkeletonCarousel()
              : const _SkeletonRail(),
          error: (_, __) => const SizedBox.shrink(),
          data: (products) {
            if (products.isEmpty) return const SizedBox.shrink();
            if (layout == RailLayout.carousel) {
              return _RailCarousel(products: products, maxItems: maxItems);
            }
            return SizedBox(
              height: 258,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = products[i];
                  return SizedBox(
                    width: 152,
                    child: ProductCard(
                      product: p,
                      isBestseller: p.isBestseller ?? false,
                      isOfficialSeller: p.isOfficialSeller ?? false,
                      basketDiscountPct: p.basketDiscountPct,
                      onTap: () => context.push('/products/${p.id}'),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Desktop/tablet horizontal carousel. Lazy `ListView.builder` driven by a
/// `ScrollController`; on desktop a `HoverRegion` fades in white circular
/// chevron cards that slide the rail one viewport at a time, disabled at the
/// scroll extents. Tablet (touch) gets the scroller without chevrons.
class _RailCarousel extends StatefulWidget {
  const _RailCarousel({required this.products, this.maxItems});

  final List<ProductSummary> products;
  final int? maxItems;

  @override
  State<_RailCarousel> createState() => _RailCarouselState();
}

class _RailCarouselState extends State<_RailCarousel> {
  // 0.62 width:height — the proven desktop card composition (former grid ratio).
  static const double _cardWidth = 200;
  static const double _railHeight = 324;
  static const double _cardGap = 12;

  final _controller = ScrollController();
  bool _atStart = true;
  bool _atEnd = true; // until first layout proves the content overflows

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final atStart = pos.pixels <= pos.minScrollExtent + 1;
    final atEnd = pos.pixels >= pos.maxScrollExtent - 1;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  void _nudge(int direction) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target = (pos.pixels + direction * pos.viewportDimension)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    unawaited(
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cap = widget.maxItems;
    final items = (cap != null && widget.products.length > cap)
        ? widget.products.sublist(0, cap)
        : widget.products;

    final list = SizedBox(
      height: _railHeight,
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final p = items[i];
          return Padding(
            padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : _cardGap),
            child: SizedBox(
              width: _cardWidth,
              child: ProductCard(
                product: p,
                isBestseller: p.isBestseller ?? false,
                isOfficialSeller: p.isOfficialSeller ?? false,
                basketDiscountPct: p.basketDiscountPct,
                onTap: () => context.push('/products/${p.id}'),
              ),
            ),
          );
        },
      ),
    );

    // Hover chevrons only where a pointer exists (desktop). Tablet = touch.
    if (!context.isDesktop) return list;

    return HoverRegion(
      builder: (context, hovering) => Stack(
        children: [
          list,
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ChevronButton(
                  icon: Icons.chevron_left_rounded,
                  visible: hovering && !_atStart,
                  onTap: () => _nudge(-1),
                ),
                _ChevronButton(
                  icon: Icons.chevron_right_rounded,
                  visible: hovering && !_atEnd,
                  onTap: () => _nudge(1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White circular floating chevron card. Fades via [AnimatedOpacity] and stops
/// intercepting taps when hidden ([IgnorePointer]).
class _ChevronButton extends StatelessWidget {
  const _ChevronButton({
    required this.icon,
    required this.visible,
    required this.onTap,
  });

  final IconData icon;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
          ignoring: !visible,
          child: Material(
            color: cs.surface,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkResponse(
              onTap: onTap,
              radius: 22,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, size: 26, color: cs.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonRail extends StatelessWidget {
  const _SkeletonRail();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 258,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, __) => const SizedBox(
          width: 152,
          child: SkeletonProductCard(),
        ),
      ),
    );
  }
}

class _SkeletonCarousel extends StatelessWidget {
  const _SkeletonCarousel();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _RailCarouselState._railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) =>
            const SizedBox(width: _RailCarouselState._cardGap),
        itemBuilder: (_, __) => const SizedBox(
          width: _RailCarouselState._cardWidth,
          child: SkeletonProductCard(),
        ),
      ),
    );
  }
}
