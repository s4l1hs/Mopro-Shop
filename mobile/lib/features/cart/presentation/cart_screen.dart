import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/core/widgets/login_required_sheet.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/widgets/cart_line_card.dart';
import 'package:mopro/features/cart/widgets/cart_totals_summary.dart';
import 'package:mopro/features/cart/widgets/empty_cart.dart';
import 'package:mopro/features/cart/widgets/order_summary_card.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:mopro/utils/money.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cartProvider);
    final cashbackAsync = ref.watch(cartMonthlyCashbackProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('cart.title'.tr()),
        actions: [
          if (state.cart.valueOrNull?.isEmpty == false)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'cart.clear'.tr(),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: state.cart.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          final appError = err is AppError
              ? err
              : UnknownError(statusCode: 0, message: err.toString());
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () => ref.read(cartProvider.notifier).refresh(),
            ),
          );
        },
        data: (cart) {
          if (cart.isEmpty) return const EmptyCart();
          if (!context.isMobile) return _buildWide(context, ref, cart);

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () =>
                      ref.read(cartProvider.notifier).refresh(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: _buildGroupedLines(context, ref, cart),
                  ),
                ),
              ),
              CartTotalsSummary(
                cart: cart,
                onCheckout: () => _checkout(context, ref),
                cashbackMonthlyMinor: cashbackAsync.valueOrNull,
              ),
            ],
          );
        },
      ),
    );
  }

  void _checkout(BuildContext context, WidgetRef ref) => requireAuth(
        context,
        ref,
        reason: 'cart.checkout_login_reason'.tr(),
        onAuthed: () => context.push('/checkout'),
      );

  // Tablet/desktop: seller-grouped items scroll on the left; the order summary
  // is fixed on the right (it sits outside the scrolling list, so it stays
  // pinned while the items scroll).
  Widget _buildWide(BuildContext context, WidgetRef ref, CartDto cart) {
    final pad = context.isDesktop ? 32.0 : 24.0;
    final summaryW = context.isDesktop ? 360.0 : 320.0;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
              child: SizedBox(
                height: constraints.maxHeight - 32,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () =>
                            ref.read(cartProvider.notifier).refresh(),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: _buildGroupedLines(context, ref, cart),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: summaryW,
                      child: SingleChildScrollView(
                        child: OrderSummaryCard(
                          onCheckout: () => _checkout(context, ref),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildGroupedLines(
    BuildContext context,
    WidgetRef ref,
    CartDto cart,
  ) {
    final grouped = <int, List<CartLineDto>>{};
    for (final line in cart.lines) {
      grouped.putIfAbsent(line.sellerId, () => []).add(line);
    }
    // CT-01: per-seller subtotal from the existing totalsBySeller (the seller
    // *name* isn't in the cart response — flagged for the backend cluster).
    int subtotalFor(int sellerId) => cart.totalsBySeller
        .where((t) => t.sellerId == sellerId)
        .fold<int>(0, (s, t) => s + t.itemsMinor);

    return grouped.entries.expand((entry) {
      final sellerId = entry.key;
      final sellerLines = entry.value;
      return [
        _SellerGroupHeader(
          label: 'cart.seller_section'.tr(namedArgs: {'seller': '#$sellerId'}),
          subtotalMinor: subtotalFor(sellerId),
        ),
        ...sellerLines.map(
          (line) => CartLineCard(
            key: ValueKey(line.id),
            line: line,
            onRemove: () => _removeWithUndo(context, ref, line),
            onMoveToFavorites: () => _moveToFavorites(context, ref, line),
            onDecrement: () => ref
                .read(cartProvider.notifier)
                .updateQty(lineId: line.id, qty: line.qty - 1),
            onIncrement: () => ref
                .read(cartProvider.notifier)
                .updateQty(lineId: line.id, qty: line.qty + 1),
          ),
        ),
      ];
    }).toList();
  }

  // CT-05: move a line to favorites — ensure it's favorited (never un-favorite),
  // then remove it from the cart.
  void _moveToFavorites(BuildContext context, WidgetRef ref, CartLineDto line) {
    if (!ref.read(isFavoriteProvider(line.productId))) {
      ref.read(favoritesProvider.notifier).toggle(line.productId);
    }
    ref.read(cartProvider.notifier).removeLine(lineId: line.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'cart.moved_to_favorites'.tr(namedArgs: {'title': line.title}),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // CT-10: real Undo — re-add the removed line (it carries product/variant/qty).
  void _removeWithUndo(
    BuildContext context,
    WidgetRef ref,
    CartLineDto line,
  ) {
    ref.read(cartProvider.notifier).removeLine(lineId: line.id);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'cart.remove_item_confirm'.tr(namedArgs: {'title': line.title}),
        ),
        action: SnackBarAction(
          label: 'common.undo'.tr(),
          onPressed: () => ref.read(cartProvider.notifier).addItem(
                productId: line.productId,
                variantId: line.variantId,
                qty: line.qty,
              ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('cart.clear_confirm_title'.tr()),
        content: Text('cart.clear_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'cart.clear'.tr(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(cartProvider.notifier).clear();
    }
  }
}

/// CT-01: seller-group header — seller label + the per-seller subtotal (from
/// `totalsBySeller`). The seller *name* isn't in the cart response (only
/// `sellerId`) → flagged for the backend cluster; the label stays `#<id>`.
class _SellerGroupHeader extends StatelessWidget {
  const _SellerGroupHeader({
    required this.label,
    required this.subtotalMinor,
  });

  final String label;
  final int subtotalMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: cs.surfaceContainerLow,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${'cart.subtotal'.tr()}: ${MoneyUtils.formatMinor(subtotalMinor)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
