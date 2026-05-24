import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/widgets/hero_carousel.dart';
import 'package:mopro/features/catalog/widgets/home_category_grid.dart';
import 'package:mopro/features/catalog/widgets/product_rail.dart';
import 'package:mopro/features/catalog/widgets/trust_bar.dart';
import 'package:mopro/features/home/providers/home_wallet_summary_provider.dart';
import 'package:mopro/features/wallet/widgets/coin_balance_pill.dart';

class CatalogHomeScreen extends ConsumerWidget {
  const CatalogHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('home.title'.tr()),
        actions: [
          const _CoinBalanceAction(),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(productsRailProvider('recommended'))
            ..invalidate(productsRailProvider('bestseller'))
            ..invalidate(productsRailProvider('newest'));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: HeroCarousel()),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            const SliverToBoxAdapter(child: HomeCategoryGrid()),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: ProductRail(
                title: 'home.section_recommended'.tr(),
                sort: 'recommended',
                seeAllRoute: '/categories',
              ),
            ),
            SliverToBoxAdapter(
              child: ProductRail(
                title: 'home.section_bestsellers'.tr(),
                sort: 'bestseller',
                seeAllRoute: '/categories',
              ),
            ),
            SliverToBoxAdapter(
              child: ProductRail(
                title: 'home.section_newest'.tr(),
                sort: 'newest',
                seeAllRoute: '/categories',
              ),
            ),
            const SliverToBoxAdapter(child: TrustBar()),
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
      data: (balance) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: CoinBalancePill(
          amountMinor: balance.amountMinor,
          currency: balance.currency,
          onTap: () => context.push('/wallet'),
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
