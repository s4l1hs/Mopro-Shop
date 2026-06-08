import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/widgets/skeleton_box.dart';

/// Horizontal category shortcut rail on Home (IA-01).
///
/// Root-category pucks (each → its PLP `/categories/:id`) followed by a trailing
/// **"Tüm Kategoriler"** puck that opens the full category tree (`/categories`).
/// Replaces the old grid now that the Categories bottom-nav tab is gone (→ Coin):
/// this rail + entry is how the full tree is reached from Home.
class HomeCategoryRail extends ConsumerWidget {
  const HomeCategoryRail({super.key});

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
          SizedBox(
            height: 84,
            child: categoriesState.categories.when(
              loading: () => ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, __) =>
                    const SkeletonBox(width: 56, height: 84),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (cats) {
                final roots = cats.where((c) => c.parentId == null).toList();
                if (roots.isEmpty) return const SizedBox.shrink();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  // roots + the trailing "all categories" entry → full tree.
                  itemCount: roots.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    if (i == roots.length) {
                      return _CategoryPuck(
                        name: 'home.all_categories'.tr(),
                        icon: Icons.apps_outlined,
                        onTap: () => context.push('/categories'),
                      );
                    }
                    final cat = roots[i];
                    return _CategoryPuck(
                      name: cat.name,
                      iconUrl: cat.iconUrl,
                      icon: _iconFor(cat.slug),
                      onTap: () => context.push(
                        '/categories/${cat.id}',
                        extra: cat.name,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPuck extends StatelessWidget {
  const _CategoryPuck({
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
      child: SizedBox(
        width: 56,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
