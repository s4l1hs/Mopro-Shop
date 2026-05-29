import 'dart:async';

import 'package:clock/clock.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/home/providers/flash_deals_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// Countdown-headed flash-deals rail. Watches [flashDealsProvider]; renders a
/// skeleton while loading and nothing when there's no active collection (the
/// rail is purely additive). The header counts down to `endsAt`; at zero it
/// switches to a muted "ended" state and the body collapses until the next
/// provider refresh.
///
/// Body layout: mobile → horizontal scroller; tablet → 3-col grid (6 items);
/// desktop → 5-col grid (10 items). Cards use [ProductCard.priceOverride] so
/// the flash price shows in brand orange with the regular price struck through.
class FlashDealsRail extends ConsumerStatefulWidget {
  const FlashDealsRail({super.key});

  @override
  ConsumerState<FlashDealsRail> createState() => _FlashDealsRailState();
}

class _FlashDealsRailState extends ConsumerState<FlashDealsRail> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // One 1s ticker drives the countdown; build() recomputes the remaining
    // time from endsAt each tick.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(flashDealsProvider).when(
          loading: () => const _FlashSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (col) {
            if (col == null) return const SizedBox.shrink();
            final remaining = col.endsAt.difference(clock.now());
            final ended = remaining.inSeconds <= 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  title: col.title,
                  ended: ended,
                  countdown: ended ? null : _fmt(remaining),
                ),
                if (!ended) _Body(products: col.products),
              ],
            );
          },
        );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.ended, this.countdown});
  final String title;
  final bool ended;
  final String? countdown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = ended ? cs.surfaceContainerHighest : MoproTokens.primaryLight;
    final fg = ended ? cs.onSurfaceVariant : Colors.white;
    return Container(
      height: 56,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              ended ? 'home.flash_deals_ended'.tr() : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (countdown != null)
            Text(
              countdown!,
              style: TextStyle(
                color: fg,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.products});
  final List<ProductSummary> products;

  Widget _card(BuildContext context, ProductSummary p) => ProductCard(
        product: p,
        priceOverride: p.flashPriceMinor,
        onTap: () => context.go('/products/${p.id}'),
      );

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) {
      return SizedBox(
        height: 366,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          itemCount: products.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => SizedBox(width: 150, child: _card(context, products[i])),
        ),
      );
    }
    final cols = context.isDesktop ? 5 : 3;
    final cap = context.isDesktop ? 10 : 6;
    final items = products.take(cap).toList();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _card(context, items[i]),
      ),
    );
  }
}

class _FlashSkeleton extends StatelessWidget {
  const _FlashSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 56, color: MoproTokens.primaryLight),
        SizedBox(
          height: 366,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, __) =>
                const SizedBox(width: 150, child: SkeletonProductCard()),
          ),
        ),
      ],
    );
  }
}
