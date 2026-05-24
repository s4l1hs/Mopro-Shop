import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/widgets/skeleton_box.dart';
import 'package:mopro_api/mopro_api.dart';

class HomeCategoryGrid extends ConsumerWidget {
  const HomeCategoryGrid({super.key});

  static const _slugIcons = <String, IconData>{
    'elektronik': Icons.devices_outlined,
    'giyim': Icons.checkroom_outlined,
    'ev-yasam': Icons.home_outlined,
    'spor': Icons.sports_basketball_outlined,
    'kitap': Icons.menu_book_outlined,
    'kozmetik': Icons.face_outlined,
    'oyun': Icons.gamepad_outlined,
    'mutfak': Icons.kitchen_outlined,
    'bebek': Icons.child_care_outlined,
    'bahce': Icons.yard_outlined,
    'otomotiv': Icons.directions_car_outlined,
    'ofis': Icons.work_outline,
  };

  static IconData _iconFor(String slug) =>
      _slugIcons[slug] ?? Icons.category_outlined;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesState = ref.watch(categoriesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'home.categories_title'.tr(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          categoriesState.categories.when(
            loading: _buildSkeleton,
            error: (_, __) => const SizedBox.shrink(),
            data: (cats) {
              final roots =
                  cats.where((c) => c.parentId == null).take(8).toList();
              if (roots.isEmpty) return const SizedBox.shrink();
              return _buildGrid(context, roots);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<Category> cats) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final cat = cats[i];
        return _CategoryCell(
          name: cat.name,
          iconUrl: cat.iconUrl,
          icon: _iconFor(cat.slug),
          onTap: () => context.push('/categories/${cat.id}', extra: cat.name),
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: 8,
      itemBuilder: (_, __) => const SkeletonBox(width: double.infinity, height: 72),
    );
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.name,
    required this.icon,
    required this.onTap,
    this.iconUrl,
  });

  final String name;
  final IconData icon;
  final VoidCallback onTap;
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: iconUrl != null && iconUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(
                      imageUrl: iconUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(
                        icon,
                        color: colorScheme.onPrimaryContainer,
                        size: 26,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    color: colorScheme.onPrimaryContainer,
                    size: 26,
                  ),
          ),
          const SizedBox(height: 5),
          Text(
            name,
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
