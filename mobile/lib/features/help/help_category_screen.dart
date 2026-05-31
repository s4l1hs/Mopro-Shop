import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/help/application/help_providers.dart';

class HelpCategoryScreen extends ConsumerWidget {
  const HelpCategoryScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final arts = ref.watch(helpArticlesProvider(slug));
    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('help.title'.tr())),
      body: arts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text('common.error'.tr())),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'help.empty_category'.tr(),
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  title: Text(list[i].title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/help/article/${list[i].slug}'),
                ),
              ),
      ),
    );
  }
}
