import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/breakpoint_resolver.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/help/application/help_providers.dart';
import 'package:mopro/features/help/widgets/help_category_card.dart';

class HelpIndexScreen extends ConsumerStatefulWidget {
  const HelpIndexScreen({super.key});

  @override
  ConsumerState<HelpIndexScreen> createState() => _HelpIndexScreenState();
}

class _HelpIndexScreenState extends ConsumerState<HelpIndexScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final q = _search.text.trim();
    if (q.isNotEmpty) context.go('/help/search?q=${Uri.encodeQueryComponent(q)}');
  }

  int _columns(BuildContext context) {
    if (context.isMobile) return 1;
    if (context.isTablet) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = ref.watch(helpCategoriesProvider);
    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('help.title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submitSearch(),
            decoration: InputDecoration(
              hintText: 'help.search_hint'.tr(),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          cats.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => Text('common.error'.tr()),
            data: (list) => GridView.count(
              crossAxisCount: _columns(context),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 3.2,
              children: [for (final c in list) HelpCategoryCard(category: c)],
            ),
          ),
          const SizedBox(height: 32),
          Text('help.cant_find'.tr(), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go('/help/contact'),
            icon: const Icon(Icons.support_agent_outlined),
            label: Text('help.contact_cta'.tr()),
          ),
        ],
      ),
    );
  }
}
