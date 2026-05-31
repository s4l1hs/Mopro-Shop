import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/help/data/help_dto.dart';

/// Maps a backend `icon_name` to a Material icon; falls back to a help glyph.
IconData helpIcon(String? name) => switch (name) {
      'person_outline' => Icons.person_outline,
      'shopping_bag_outlined' => Icons.shopping_bag_outlined,
      'assignment_return_outlined' => Icons.assignment_return_outlined,
      'shield_outlined' => Icons.shield_outlined,
      _ => Icons.help_outline_rounded,
    };

class HelpCategoryCard extends StatelessWidget {
  const HelpCategoryCard({required this.category, super.key});

  final HelpCategoryDto category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      label: category.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go('/help/category/${category.slug}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(helpIcon(category.iconName), size: 32, color: cs.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'help.article_count'.tr(args: ['${category.articleCount}']),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
