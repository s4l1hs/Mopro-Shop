import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/utils/coin_formatter.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/design/responsive/pointer_kind.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/design/widgets/mopro_share_button.dart';
import 'package:mopro/features/analytics/analytics_service.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/catalog/data/similar_products_provider.dart';
import 'package:mopro/features/catalog/pdp/qa/pdp_qa_tab.dart';
import 'package:mopro/features/catalog/pdp/reviews/pdp_reviews_tab.dart';
import 'package:mopro/features/catalog/pdp/reviews/reviews_provider.dart';
import 'package:mopro/features/catalog/providers/product_detail_provider.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_delivery_info.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_image_pager.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_price_block.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_seller_card.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_sticky_cta.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_variant_selector.dart';
import 'package:mopro/features/catalog/widgets/pdp_image_gallery.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/catalog/widgets/product_list_rail.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:mopro/features/growth/meta_tags_service.dart';
import 'package:mopro/features/growth/seo_head.dart';
import 'package:mopro/features/growth/structured_data_service.dart';
import 'package:mopro_api/mopro_api.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({required this.productId, super.key});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(productDetailProvider(productId));

    return state.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) {
        final appError = err is AppError
            ? err
            : UnknownError(statusCode: 0, message: err.toString());
        if (appError is NotFoundError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('product.not_found'.tr())),
          );
        }
        return Scaffold(
          appBar: AppBar(),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () =>
                  ref.read(productDetailProvider(productId).notifier).refresh(),
            ),
          ),
        );
      },
      data: (product) => _ProductDetailBody(product: product),
    );
  }
}

class _ProductDetailBody extends ConsumerStatefulWidget {
  const _ProductDetailBody({required this.product});

  final Product product;

  @override
  ConsumerState<_ProductDetailBody> createState() => _ProductDetailBodyState();
}

class _ProductDetailBodyState extends ConsumerState<_ProductDetailBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Variant? _selectedVariant;

  // Wide (tablet/desktop) layout state.
  final ScrollController _wideScroll = ScrollController();
  final GlobalKey wideGalleryKey = GlobalKey();
  final GlobalKey wideTabsKey = GlobalKey();
  final GlobalKey _buyBoxKey = GlobalKey();
  double _scrollOffset = 0;
  double? _buyBoxHeight;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    // analytics: product_view — manual emission on PDP mount (design §7).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(analyticsServiceProvider).track(
            // categoryId is additive (P-033) — enables per-category popularity
            // (P-031). The loaded product always carries its category here.
            AnalyticsEvent('product_view', {
              'productId': widget.product.id,
              'categoryId': widget.product.categoryId,
            }),
          );
    });
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.product.variants.isNotEmpty) {
      _selectedVariant = widget.product.variants.first;
    }
    _wideScroll.addListener(() {
      if (mounted) setState(() => _scrollOffset = _wideScroll.offset);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _wideScroll.dispose();
    super.dispose();
  }

  void _selectVariant(Variant v) => setState(() => _selectedVariant = v);

  List<String> get _imageUrls =>
      (_selectedVariant?.imageUrls.isNotEmpty ?? false)
          ? _selectedVariant!.imageUrls
          : widget.product.variants.firstOrNull?.imageUrls ?? [];

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final webBase = ref.watch(webBaseUrlProvider);
    final url = '$webBase/products/${product.id}';
    final cheapest = product.variants.isEmpty
        ? null
        : product.variants
            .reduce((a, b) => a.priceMinor <= b.priceMinor ? a : b);
    return SeoHead(
      meta: MetaTagsInput(
        title: '${product.title} — Mopro',
        description: seoDescription(product.description),
        imageUrl: _imageUrls.firstOrNull,
        canonicalUrl: url,
        openGraphExtras: const {'og:type': 'product'},
      ),
      jsonLd: productJsonLd(
        name: product.title,
        description: seoDescription(product.description),
        url: url,
        image: _imageUrls.firstOrNull,
        brand: product.brand,
        priceMinor: cheapest?.priceMinor,
        priceCurrency: cheapest?.priceCurrency,
      ),
      child: context.isMobile ? _buildMobile(context) : _buildWide(context),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final product = widget.product;
    final isMutating = ref.watch(cartProvider).isMutating;
    final isFav = ref.watch(isFavoriteProvider(product.id));
    final imageUrls = _imageUrls;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: MediaQuery.of(context).size.width,
            pinned: true,
            stretch: true,
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                tooltip: isFav
                    ? 'product.remove_from_favorites'.tr()
                    : 'product.add_to_favorites'.tr(),
                onPressed: () =>
                    ref.read(favoritesProvider.notifier).toggle(product.id),
              ),
              MoproShareButton(
                url: '${ref.watch(webBaseUrlProvider)}/products/${product.id}',
                title: product.title,
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: PdpImageGallery(
                imageUrls: imageUrls,
                heroTag: 'product-image-${product.id}',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _BuyBox(
              product: product,
              selectedVariant: _selectedVariant,
              onVariantChanged: (v) => setState(() => _selectedVariant = v),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'product.description_tab'.tr()),
                  Tab(text: 'product.specs_tab'.tr()),
                  Tab(text: 'product.reviews_tab'.tr()),
                  Tab(text: 'product.qa_tab'.tr()),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _DescriptionTab(
              description: product.description,
              productId: product.id,
            ),
            const _StubTab(),
            PdpReviewsTab(productId: product.id),
            PdpQaTab(productId: product.id),
          ],
        ),
      ),
      bottomNavigationBar: PdpStickyCta(
        selectedVariant: _selectedVariant,
        isMutating: isMutating,
        onAddToCart: () => _addToCart(context),
      ),
    );
  }

  Future<void> _addToCart(BuildContext context) async {
    final variant = _selectedVariant;
    if (variant == null) return;
    try {
      await ref.read(cartProvider.notifier).addItem(
            productId: widget.product.id,
            variantId: variant.id,
            qty: _quantity,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('cart.added_to_cart'.tr()),
            action: SnackBarAction(
              label: 'nav.cart'.tr(),
              onPressed: () => context.push('/cart'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('cart.add_failed'.tr())),
        );
      }
    }
  }

  // ── Wide (tablet/desktop) two-column layout ─────────────────────────────────

  void _scrollToReviews() {
    _tabController.index = 2;
    final ctx = wideTabsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  Widget _buildWide(BuildContext context) {
    final product = widget.product;
    final isMutating = ref.watch(cartProvider).isMutating;
    final isFav = ref.watch(isFavoriteProvider(product.id));

    // Measure the buy-box height after layout so the sticky gallery column (a
    // Stack) is bounded by the taller of the two columns.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _buyBoxKey.currentContext?.size?.height;
      if (h != null && h != _buyBoxHeight && mounted) {
        setState(() => _buyBoxHeight = h);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title:
            Text(product.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
            tooltip: isFav
                ? 'product.remove_from_favorites'.tr()
                : 'product.add_to_favorites'.tr(),
            onPressed: () =>
                ref.read(favoritesProvider.notifier).toggle(product.id),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        controller: _wideScroll,
        child: CenteredContentColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (ctx, c) {
                  final isDesktop = context.isDesktop;
                  final buyBoxW = isDesktop ? 480.0 : 360.0;
                  const gap = 32.0;
                  final galleryW = (c.maxWidth - buyBoxW - gap)
                      .clamp(280.0, isDesktop ? 600.0 : 480.0);
                  final galleryH = galleryW + 84; // square image + thumb strip
                  final contentH =
                      math.max(galleryH, _buyBoxHeight ?? galleryH);
                  final maxTop =
                      (contentH - galleryH).clamp(0.0, double.infinity);
                  final top = _scrollOffset.clamp(0.0, maxTop);

                  // NOTE: the Row is NOT height-constrained — the buy-box must
                  // measure its natural height (via _buyBoxKey) so contentH can
                  // grow to it. Only the gallery cell is sized to contentH, so
                  // the gallery can translate within the taller column.
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: galleryW,
                        height: contentH,
                        child: Stack(
                          children: [
                            Positioned(
                              top: top,
                              left: 0,
                              right: 0,
                              height: galleryH,
                              child: KeyedSubtree(
                                key: wideGalleryKey,
                                child: ValueListenableBuilder<LastPointerKind>(
                                  valueListenable: PointerKindObserver.lastKind,
                                  builder: (_, kind, __) => PdpImagePager(
                                    imageUrls: _imageUrls,
                                    enableHoverZoom: isDesktop &&
                                        kind == LastPointerKind.mouse,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: gap),
                      SizedBox(
                        width: buyBoxW,
                        child: KeyedSubtree(
                          key: _buyBoxKey,
                          child: _buildWideBuyBox(context, product, isMutating),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              KeyedSubtree(
                key: wideTabsKey,
                child: _buildWideTabs(context, product),
              ),
              const SizedBox(height: 24),
              _SimilarProductsRail(productId: product.id),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideBuyBox(
    BuildContext context,
    Product product,
    bool isMutating,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = _selectedVariant;
    final summary = ref.watch(reviewsNotifierProvider(product.id)).summary;
    final ratingCount = summary?.totalCount ?? 0;
    final avg = summary?.average ?? 0.0;
    final titleSize = context.isDesktop ? 24.0 : 20.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () =>
              context.push('/search?q=${Uri.encodeComponent(product.brand)}'),
          child: Text(
            product.brand,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.primary, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          product.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(fontSize: titleSize),
        ),
        if (ratingCount > 0) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: _scrollToReviews,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: MoproTokens.ratingStar,
                ),
                const SizedBox(width: 4),
                Text(avg.toStringAsFixed(1), style: theme.textTheme.bodyMedium),
                const SizedBox(width: 6),
                Text(
                  'product.review_count'
                      .tr(namedArgs: {'count': '$ratingCount'}),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (v != null) ...[
          PdpPriceBlock(
            priceMinor: v.priceMinor,
            originalPriceMinor: v.originalPriceMinor,
            lowestIn30DaysMinor: v.lowest30dPriceMinor,
          ),
          const SizedBox(height: 6),
          _StockPill(stock: v.stock),
        ],
        if (product.deliveryEta != null) ...[
          const SizedBox(height: 16),
          PdpDeliveryInfo(eta: product.deliveryEta!),
        ],
        const SizedBox(height: 16),
        _CashbackCard(preview: product.cashbackPreview),
        if (product.variants.length > 1) ...[
          const SizedBox(height: 16),
          PdpVariantSelector(
            variants: product.variants,
            selected: v,
            onChanged: _selectVariant,
          ),
        ],
        const SizedBox(height: 16),
        PdpSellerCard(
          sellerName: product.sellerName,
          // Route to the seller storefront only when the slug resolved; a null
          // slug (legacy/platform-direct or suspended seller) hides the link.
          onTap: (product.sellerSlug != null && product.sellerSlug!.isNotEmpty)
              ? () => context.push('/sellers/${product.sellerSlug}')
              : null,
        ),
        const SizedBox(height: 16),
        _QuantityStepper(
          quantity: _quantity,
          onChanged: (q) => setState(() => _quantity = q),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed:
                v != null && !isMutating ? () => _addToCart(context) : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: Text('product.add_to_cart'.tr()),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () =>
                ref.read(favoritesProvider.notifier).toggle(product.id),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: cs.primary),
              foregroundColor: cs.primary,
            ),
            child: Text('product.add_to_favorites'.tr()),
          ),
        ),
        const SizedBox(height: 24),
        const _TrustBadges(),
      ],
    );
  }

  Widget _buildWideTabs(BuildContext context, Product product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'product.description_tab'.tr()),
            Tab(text: 'product.specs_tab'.tr()),
            Tab(text: 'product.reviews_tab'.tr()),
            Tab(text: 'product.qa_tab'.tr()),
          ],
        ),
        const SizedBox(height: 16),
        switch (_tabController.index) {
          0 => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: MarkdownBody(data: product.description),
            ),
          2 => PdpReviewsTab(productId: product.id, scrollable: false),
          3 => PdpQaTab(productId: product.id, scrollable: false),
          _ => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'common.loading'.tr(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        },
      ],
    );
  }
}

// ── Buy Box ────────────────────────────────────────────────────────────────────

class _BuyBox extends StatelessWidget {
  const _BuyBox({
    required this.product,
    required this.selectedVariant,
    required this.onVariantChanged,
  });

  final Product product;
  final Variant? selectedVariant;
  final ValueChanged<Variant> onVariantChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(product.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'product.sold_by'.tr(namedArgs: {'seller': product.sellerName}),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (selectedVariant != null) ...[
            PdpPriceBlock(
              priceMinor: selectedVariant!.priceMinor,
              originalPriceMinor: selectedVariant!.originalPriceMinor,
              lowestIn30DaysMinor: selectedVariant!.lowest30dPriceMinor,
            ),
            const SizedBox(height: 6),
            _StockPill(stock: selectedVariant!.stock),
          ],
          if (product.deliveryEta != null) ...[
            const SizedBox(height: 16),
            PdpDeliveryInfo(eta: product.deliveryEta!),
          ],
          const SizedBox(height: 16),
          _CashbackCard(preview: product.cashbackPreview),
          if (product.variants.length > 1) ...[
            const SizedBox(height: 16),
            PdpVariantSelector(
              variants: product.variants,
              selected: selectedVariant,
              onChanged: onVariantChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _StockPill extends StatelessWidget {
  const _StockPill({required this.stock});

  final int stock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (stock <= 0) {
      return _Pill(
        label: 'product.out_of_stock'.tr(),
        color: colorScheme.errorContainer,
        textColor: colorScheme.onErrorContainer,
      );
    }
    if (stock <= 5) {
      return _Pill(
        label: 'product.low_stock'.tr(namedArgs: {'count': stock.toString()}),
        color: colorScheme.tertiaryContainer,
        textColor: colorScheme.onTertiaryContainer,
      );
    }
    return _Pill(
      label: 'product.in_stock'.tr(),
      color: colorScheme.secondaryContainer,
      textColor: colorScheme.onSecondaryContainer,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}

class _CashbackCard extends StatelessWidget {
  const _CashbackCard({required this.preview});

  final CashbackPreview preview;

  @override
  Widget build(BuildContext context) {
    if (preview.monthlyCoinMinor <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.currency_exchange,
                size: 16,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'cashback.preview_title'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'cashback.cashback_preview'.tr(
              namedArgs: {
                'monthly': formatCoin(
                  preview.monthlyCoinMinor,
                  preview.currency,
                ),
              },
            ),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 4),
          Text(
            'cashback.perpetual_note'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onPrimaryContainer.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab bar delegate ─────────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) => old.tabBar != tabBar;
}

// ── Tab contents ─────────────────────────────────────────────────────────────

class _DescriptionTab extends ConsumerWidget {
  const _DescriptionTab({
    required this.description,
    required this.productId,
  });

  final String description;
  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relatedAsync = ref.watch(similarProductsProvider(productId));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(data: description),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
            child: Text(
              'product.related_title'.tr(),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 258,
            child: relatedAsync.when(
              loading: () => ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, __) => const SizedBox(
                  width: 152,
                  child: SkeletonProductCard(),
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (products) {
                final filtered =
                    products.where((p) => p.id != productId).take(4).toList();
                if (filtered.isEmpty) return const SizedBox.shrink();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    return SizedBox(
                      width: 152,
                      child: ProductCard(
                        product: p,
                        onTap: () => context.push('/products/${p.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// "Benzer ürünler" rail fed by co-view recommendations
/// ([similarProductsProvider]). Renders zero space while loading or on
/// empty/error (defensive layering) — the PDP layout is unchanged when there
/// are no recommendations.
class _SimilarProductsRail extends ConsumerWidget {
  const _SimilarProductsRail({required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products =
        ref.watch(similarProductsProvider(productId)).valueOrNull ?? const [];
    if (products.isEmpty) return const SizedBox.shrink();
    return ProductListRail(
      products: products,
      title: 'product.related_title'.tr(),
    );
  }
}

class _StubTab extends StatelessWidget {
  const _StubTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'common.loading'.tr(),
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// ── Wide buy-box helpers ───────────────────────────────────────────────────────

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn(IconData icon, String label, VoidCallback? onTap) => SizedBox(
          width: 44,
          height: 44,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: BorderSide(color: cs.outlineVariant),
            ),
            // Tooltip inside the button (like IconButton.tooltip) so the name
            // merges down into the button's semantics node.
            child: Tooltip(
              message: label,
              child: Icon(icon, size: 18, semanticLabel: label),
            ),
          ),
        );
    return Row(
      children: [
        btn(Icons.remove, 'product.decrease_qty'.tr(),
            quantity > 1 ? () => onChanged(quantity - 1) : null,),
        SizedBox(
          width: 48,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        btn(Icons.add, 'product.increase_qty'.tr(),
            () => onChanged(quantity + 1),),
      ],
    );
  }
}

class _TrustBadges extends StatelessWidget {
  const _TrustBadges();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget badge(IconData icon, String key) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 24, color: cs.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(
                key.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badge(Icons.lock_outline, 'product.trust_secure_payment'),
        badge(Icons.refresh, 'product.trust_easy_return'),
        badge(Icons.local_shipping_outlined, 'product.trust_free_shipping'),
      ],
    );
  }
}
