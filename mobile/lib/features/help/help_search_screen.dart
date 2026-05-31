import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/help/application/help_providers.dart';

class HelpSearchScreen extends ConsumerStatefulWidget {
  const HelpSearchScreen({required this.query, super.key});

  final String query;

  @override
  ConsumerState<HelpSearchScreen> createState() => _HelpSearchScreenState();
}

class _HelpSearchScreenState extends ConsumerState<HelpSearchScreen> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.query);
  late String _query = widget.query;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // 300ms debounce: refine the query without a fetch on every keystroke.
  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = ref.watch(helpSearchProvider(_query));
    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('help.search_results_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'help.search_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(child: Text('common.error'.tr())),
              data: (list) => list.isEmpty
                  ? _Empty(onContact: () => context.go('/help/contact'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = list[i];
                        return ListTile(
                          title: MarkdownBody(
                            data: r.title,
                            styleSheet: MarkdownStyleSheet.fromTheme(theme),
                          ),
                          subtitle: MarkdownBody(
                            data: r.snippet,
                            styleSheet: MarkdownStyleSheet.fromTheme(theme),
                          ),
                          trailing: Chip(
                            label: Text(r.categorySlug),
                            visualDensity: VisualDensity.compact,
                          ),
                          onTap: () => context.go('/help/article/${r.slug}'),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onContact});
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('help.search_empty'.tr(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onContact,
              icon: const Icon(Icons.support_agent_outlined),
              label: Text('help.contact_cta'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
