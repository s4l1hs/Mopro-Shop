import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/widgets/mopro_share_button.dart';
import 'package:mopro/features/catalog/widgets/product_grid.dart';
import 'package:mopro/features/growth/meta_tags_service.dart';
import 'package:mopro/features/growth/seo_head.dart';
import 'package:mopro/features/seller/data/seller_storefront_repository.dart';
import 'package:mopro/features/seller/providers/seller_storefront_provider.dart';
import 'package:mopro/widgets/star_rating.dart';

/// Public seller storefront, reachable at `/sellers/{slug}`. Three tabs:
/// Hakkımızda (about + rating), Ürünler (paginated grid), Yorumlar (paginated
/// reviews across the seller's products).
class SellerStorefrontScreen extends ConsumerStatefulWidget {
  const SellerStorefrontScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<SellerStorefrontScreen> createState() =>
      _SellerStorefrontScreenState();
}

class _SellerStorefrontScreenState extends ConsumerState<SellerStorefrontScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(sellerProfileProvider(widget.slug));

    final profile = profileAsync.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile?.displayName ?? 'seller_storefront.title'.tr(),
        ),
        actions: [
          if (profile != null)
            MoproShareButton(
              url: '${ref.watch(webBaseUrlProvider)}/sellers/${widget.slug}',
              title: profile.displayName,
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'seller_storefront.tab_about'.tr()),
            Tab(text: 'seller_storefront.tab_products'.tr()),
            Tab(text: 'seller_storefront.tab_reviews'.tr()),
          ],
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ErrorState(
          onRetry: () {
            ref.invalidate(sellerProfileProvider(widget.slug));
          },
        ),
        data: (profile) => SeoHead(
          meta: MetaTagsInput(
            title: '${profile.displayName} — Mopro',
            description: seoDescription(profile.bio),
            imageUrl: profile.bannerImageUrl,
            canonicalUrl: '${ref.watch(webBaseUrlProvider)}/sellers/${widget.slug}',
            openGraphExtras: const {'og:type': 'website'},
          ),
          child: TabBarView(
            controller: _tabs,
            children: [
              _AboutTab(profile: profile),
              _ProductsTab(slug: widget.slug),
              _ReviewsTab(slug: widget.slug),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.profile});

  final SellerProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (profile.bannerImageUrl != null &&
            profile.bannerImageUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: profile.bannerImageUrl!,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              backgroundImage: (profile.logoImageUrl != null &&
                      profile.logoImageUrl!.isNotEmpty)
                  ? CachedNetworkImageProvider(profile.logoImageUrl!)
                  : null,
              child: (profile.logoImageUrl == null ||
                      profile.logoImageUrl!.isEmpty)
                  ? const Icon(Icons.storefront_outlined)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  if (profile.ratingCount > 0)
                    Row(
                      children: [
                        StarRating(rating: profile.ratingAvg),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'seller_storefront.rating_summary'.tr(
                              namedArgs: {
                                'avg': profile.ratingAvg.toStringAsFixed(1),
                                'count': '${profile.ratingCount}',
                              },
                            ),
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'seller_storefront.no_ratings'.tr(),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (profile.bio.isNotEmpty)
          Text(profile.bio, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sellerProductsProvider(slug));
    final notifier = ref.read(sellerProductsProvider(slug).notifier);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return _ErrorState(onRetry: notifier.refresh);
    }
    if (state.items.isEmpty) {
      return Center(child: Text('seller_storefront.no_products'.tr()));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400 &&
            state.hasMore &&
            !state.loadingMore) {
          notifier.loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: ProductGrid(
                products: state.items,
                onProductTap: (p) => context.push('/products/${p.id}'),
              ),
            ),
            if (state.loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewsTab extends ConsumerWidget {
  const _ReviewsTab({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sellerReviewsProvider(slug));
    final notifier = ref.read(sellerReviewsProvider(slug).notifier);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return _ErrorState(onRetry: notifier.refresh);
    }
    if (state.items.isEmpty) {
      return Center(child: Text('seller_storefront.no_reviews'.tr()));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400 &&
            state.hasMore &&
            !state.loadingMore) {
          notifier.loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: state.items.length + (state.loadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const Divider(height: 24),
          itemBuilder: (context, i) {
            if (i >= state.items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _SellerReviewRow(review: state.items[i]);
          },
        ),
      ),
    );
  }
}

class _SellerReviewRow extends StatelessWidget {
  const _SellerReviewRow({required this.review});

  final SellerReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StarRating(rating: review.rating.toDouble(), size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                review.productTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        if (review.title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            review.title,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        if (review.body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(review.body, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('seller_storefront.load_error'.tr()),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: Text('seller_storefront.retry'.tr()),
          ),
        ],
      ),
    );
  }
}
