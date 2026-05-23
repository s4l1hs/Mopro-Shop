import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/empty_state.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/widgets/category_grid.dart';
import 'package:mopro_api/mopro_api.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('catalog.categories'.tr())),
      body: state.categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          final appError = err is AppError
              ? err
              : UnknownError(statusCode: 0, message: err.toString());
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () =>
                  ref.read(categoriesProvider.notifier).refresh(),
            ),
          );
        },
        data: (categories) {
          if (categories.isEmpty) {
            return EmptyState.empty();
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(categoriesProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: CategoryGrid(
                    categories: categories,
                    onCategoryTap: (cat) =>
                        context.push('/categories/${cat.id}', extra: cat.name),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
