import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// Grid columns per breakpoint — matches the favorites grid (2 / 4 / 5).
int _columns(BuildContext context) =>
    context.isDesktop ? 5 : (context.isTablet ? 4 : 2);

/// `/account/browsing-history` — the see-all surface for the recently-viewed
/// rail (Tranche 4c carry). Reads [recentlyViewedProvider] directly; "Geçmişi
/// sil" reuses the consent erase endpoint.
class BrowsingHistoryScreen extends ConsumerWidget {
  const BrowsingHistoryScreen({super.key});

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('browsing_history.confirm_title'.tr()),
        content: Text('browsing_history.confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('browsing_history.confirm_cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.primary,
            ),
            child: Text('browsing_history.confirm_delete'.tr()),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    final ok = await ref.read(userConsentProvider.notifier).deleteAllData();
    if (ok) ref.invalidate(recentlyViewedProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'browsing_history.deleted_toast'.tr()
              : 'consent.delete_error'.tr(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(recentlyViewedProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('browsing_history.title'.tr())),
      body: _Body(
        products: products,
        onClear: products.isEmpty ? null : () => _clear(context, ref),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.products, required this.onClear});

  final List<ProductSummary> products;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'browsing_history.title'.tr(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'browsing_history.subtitle'.tr(),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (onClear != null)
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text('browsing_history.clear'.tr()),
            ),
        ],
      ),
    );

    final body = products.isEmpty
        ? const _EmptyState()
        : GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns(context),
              childAspectRatio: 0.62,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: products.length,
            itemBuilder: (ctx, i) {
              final p = products[i];
              return ProductCard(
                product: p,
                isBestseller: p.isBestseller ?? false,
                basketDiscountPct: p.basketDiscountPct,
                onTap: () => ctx.push('/products/${p.id}'),
              );
            },
          );

    final content = Column(children: [header, Expanded(child: body)]);
    return context.isMobile
        ? content
        : CenteredContentColumn(child: content);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'browsing_history.empty_title'.tr(),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
            ),
            child: Text('browsing_history.empty_cta'.tr()),
          ),
        ],
      ),
    );
  }
}
