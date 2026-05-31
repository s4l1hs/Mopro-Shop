import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/design/responsive/breakpoint_resolver.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/help/application/help_providers.dart';
import 'package:mopro/features/help/data/help_dto.dart';
import 'package:mopro/features/help/widgets/contact_form_content.dart';

class ContactFormScreen extends ConsumerWidget {
  const ContactFormScreen({this.articleSlug, this.orderId, super.key});

  final String? articleSlug;
  final int? orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve the article title for subject pre-fill (if routed from an article).
    String? articleTitle;
    if (articleSlug != null) {
      articleTitle = ref.watch(helpArticleProvider(articleSlug!)).valueOrNull?.title;
    }
    final content = ContactFormContent(
      articleSlug: articleSlug,
      articleTitle: articleTitle,
      initialCategory: orderId != null ? TicketCategory.orderIssue : null,
      initialOrderId: orderId,
    );

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('help.contact_title'.tr())),
      body: context.isMobile
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: content,
            )
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Card(
                    child: Padding(padding: const EdgeInsets.all(24), child: content),
                  ),
                ),
              ),
            ),
    );
  }
}
