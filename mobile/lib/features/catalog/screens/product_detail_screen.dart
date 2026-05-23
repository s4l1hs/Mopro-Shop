import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/utils/coin_formatter.dart';
import 'package:mopro/core/widgets/empty_state.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/catalog/providers/product_detail_provider.dart';
import 'package:mopro_api/mopro_api.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({required this.productId, super.key});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(productDetailProvider(productId));

    return Scaffold(
      appBar: AppBar(),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          final appError = err is AppError
              ? err
              : UnknownError(statusCode: 0, message: err.toString());
          if (appError is NotFoundError) {
            return EmptyState.notFound();
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () => ref
                  .read(productDetailProvider(productId).notifier)
                  .refresh(),
            ),
          );
        },
        data: (product) => _ProductDetailBody(product: product),
      ),
    );
  }
}

class _ProductDetailBody extends ConsumerStatefulWidget {
  const _ProductDetailBody({required this.product});

  final Product product;

  @override
  ConsumerState<_ProductDetailBody> createState() =>
      _ProductDetailBodyState();
}

class _ProductDetailBodyState extends ConsumerState<_ProductDetailBody> {
  Variant? _selectedVariant;

  @override
  void initState() {
    super.initState();
    if (widget.product.variants.isNotEmpty) {
      _selectedVariant = widget.product.variants.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMutating = ref.watch(cartProvider).isMutating;

    final coverUrl = _selectedVariant?.imageUrls.firstOrNull ??
        product.variants.firstOrNull?.imageUrls.firstOrNull;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: AspectRatio(
              aspectRatio: 1,
              child: coverUrl != null && coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _placeholder(colorScheme),
                    )
                  : _placeholder(colorScheme),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'product.sold_by'.tr(
                      namedArgs: {'seller': product.sellerName},
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedVariant != null)
                    Text(
                      NumberFormat.currency(
                        locale: 'tr_TR',
                        symbol: '₺',
                        decimalDigits: 2,
                      ).format(_selectedVariant!.priceMinor / 100.0),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  const SizedBox(height: 16),
                  _CashbackPreviewCard(preview: product.cashbackPreview),
                  const SizedBox(height: 16),
                  if (product.variants.length > 1) ...[
                    Text(
                      'product.select_variant'.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: product.variants.map((v) {
                        final selected = _selectedVariant?.id == v.id;
                        return FilterChip(
                          label: Text(_variantLabel(v)),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _selectedVariant = v),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    product.description,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _selectedVariant != null && !isMutating
                ? () => _addToCart(context)
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: isMutating
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('product.add_to_cart'.tr()),
          ),
        ),
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
            qty: 1,
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

  Widget _placeholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_outlined, size: 64, color: cs.outlineVariant),
      );

  String _variantLabel(Variant v) {
    final parts = <String>[];
    if (v.color != null && v.color!.isNotEmpty) parts.add(v.color!);
    if (v.size != null && v.size!.isNotEmpty) parts.add(v.size!);
    return parts.isEmpty ? v.sku : parts.join(' / ');
  }
}

class _CashbackPreviewCard extends StatelessWidget {
  const _CashbackPreviewCard({required this.preview});

  final CashbackPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.currency_exchange,
                  color: colorScheme.onPrimaryContainer, size: 18),
              const SizedBox(width: 8),
              Text(
                'cashback.preview_title'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'cashback.cashback_preview'.tr(
              namedArgs: {
                'monthly': formatCoin(
                  preview.monthlyCoinMinor,
                  preview.currency,
                  compact: true,
                ),
              },
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onPrimaryContainer,
            ),
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
