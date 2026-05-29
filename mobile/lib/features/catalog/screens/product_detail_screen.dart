import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/utils/coin_formatter.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/design/responsive/pointer_kind.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/catalog/providers/product_detail_provider.dart';
import 'package:mopro/features/catalog/providers/product_reviews_provider.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_image_pager.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_price_block.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_seller_card.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_sticky_cta.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_variant_selector.dart';
import 'package:mopro/features/catalog/widgets/pdp_image_gallery.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/catalog/widgets/product_rail.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
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
            body: const Center(child: Text('Ürün bulunamadı.')),
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
    if (!context.isMobile) return _buildWide(context);
    return _buildMobile(context);
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
                onPressed: () =>
                    ref.read(favoritesProvider.notifier).toggle(product.id),
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
              onVariantChanged: (v) =>
                  setState(() => _selectedVariant = v),
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
            _ReviewsTab(productId: product.id),
            const _StubTab(),
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
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
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
        title: Text(product.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
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
                  final contentH = math.max(galleryH, _buyBoxHeight ?? galleryH);
                  final maxTop =
                      (contentH - galleryH).clamp(0.0, double.infinity);
                  final top = _scrollOffset.clamp(0.0, maxTop);

                  return SizedBox(
                    height: contentH,
                    child: Row(
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
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              KeyedSubtree(
                key: wideTabsKey,
                child: _buildWideTabs(context, product),
              ),
              const SizedBox(height: 24),
              ProductRail(
                title: 'product.related_title'.tr(),
                sort: 'recommended',
                layout: RailLayout.grid,
                gridColumns: context.isDesktop ? 6 : 3,
                maxItems: 6,
              ),
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
    final reviews =
        ref.watch(productReviewsProvider(product.id)).valueOrNull ?? [];
    final ratingCount = reviews.length;
    final avg = ratingCount == 0
        ? 0.0
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) / ratingCount;
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
                const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFB400)),
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
          PdpPriceBlock(priceMinor: v.priceMinor),
          const SizedBox(height: 6),
          _StockPill(stock: v.stock),
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
        PdpSellerCard(sellerName: product.sellerName, onTap: () {}),
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
          2 => _WideReviews(productId: product.id),
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
            PdpPriceBlock(priceMinor: selectedVariant!.priceMinor),
            const SizedBox(height: 6),
            _StockPill(stock: selectedVariant!.stock),
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
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: textColor),
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
    final relatedAsync = ref.watch(productsRailProvider('recommended'));

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

class _ReviewsTab extends ConsumerWidget {
  const _ReviewsTab({required this.productId});
  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(productReviewsProvider(productId));
    final cs = Theme.of(context).colorScheme;

    return reviewsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Yorumlar yüklenemedi.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ),
      data: (reviews) {
        if (reviews.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  size: 48,
                  color: cs.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'Henüz yorum yok.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  'İlk yorumu sen yaz!',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: reviews.length,
          separatorBuilder: (_, __) => const Divider(height: 24),
          itemBuilder: (_, i) => _ReviewItem(review: reviews[i]),
        );
      },
    );
  }
}

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({required this.review});
  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Star row
            Row(
              children: List.generate(5, (i) {
                final filled = i < review.rating;
                return Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 16,
                  color: filled
                      ? const Color(0xFFFFB400)
                      : cs.outlineVariant,
                );
              }),
            ),
            const SizedBox(width: 8),
            Text(
              review.createdAt.split('T').first,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        if (review.title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            review.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
        if (review.body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            review.body,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (review.helpfulCount > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.thumb_up_outlined,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${review.helpfulCount} kişi faydalı buldu',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ],
      ],
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
    Widget btn(IconData icon, VoidCallback? onTap) => SizedBox(
          width: 44,
          height: 44,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Icon(icon, size: 18),
          ),
        );
    return Row(
      children: [
        btn(Icons.remove, quantity > 1 ? () => onChanged(quantity - 1) : null),
        SizedBox(
          width: 48,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        btn(Icons.add, () => onChanged(quantity + 1)),
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

class _WideReviews extends ConsumerWidget {
  const _WideReviews({required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(productReviewsProvider(productId));
    final cs = Theme.of(context).colorScheme;
    return reviewsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Yorumlar yüklenemedi.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ),
      data: (reviews) {
        if (reviews.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Henüz yorum yok.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          );
        }
        return Column(
          children: [
            for (final r in reviews)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _ReviewItem(review: r),
              ),
          ],
        );
      },
    );
  }
}
