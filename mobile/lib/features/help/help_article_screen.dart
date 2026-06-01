import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/widgets/mopro_share_button.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/growth/meta_tags_service.dart';
import 'package:mopro/features/growth/seo_head.dart';
import 'package:mopro/features/help/application/help_providers.dart';

class HelpArticleScreen extends ConsumerWidget {
  const HelpArticleScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final article = ref.watch(helpArticleProvider(slug));
    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('help.title'.tr())),
      body: article.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text('common.error'.tr())),
        data: (a) => SeoHead(
          meta: MetaTagsInput(
            title: '${a.title} — Mopro Yardım',
            description: seoDescription(a.body),
            canonicalUrl: '${ref.watch(webBaseUrlProvider)}/help/article/$slug',
            openGraphExtras: const {'og:type': 'article'},
          ),
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              header: true,
              child: Text(
                a.title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            MarkdownBody(
              data: a.body,
              onTapLink: (text, href, title) {
                // Internal app-path links route via go_router; external links
                // render as styled text (no url_launcher in the app yet).
                if (href != null && href.startsWith('/')) context.go(href);
              },
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                a: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MoproShareButton(
                url: '${ref.watch(webBaseUrlProvider)}/help/article/$slug',
                title: a.title,
              ),
            ),
            const SizedBox(height: 24),
            _Feedback(),
            const Divider(height: 32),
            Text('help.unsolved'.tr(), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.go('/help/contact?article=$slug'),
              icon: const Icon(Icons.support_agent_outlined),
              label: Text('help.contact_cta'.tr()),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// Visual-only article feedback (analytics wiring is Backlog).
class _Feedback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('help.article_helpful'.tr())),
        IconButton(
          icon: const Icon(Icons.thumb_up_outlined),
          tooltip: 'help.feedback_yes'.tr(),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.thumb_down_outlined),
          tooltip: 'help.feedback_no'.tr(),
          onPressed: () {},
        ),
      ],
    );
  }
}
