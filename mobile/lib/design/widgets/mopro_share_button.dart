import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/growth/share_service.dart';

/// Brand-orange share button used on public content (PDP, category, help
/// article, seller storefront). Invokes the platform share sheet via
/// [ShareService]; on the web clipboard fallback it shows a "link copied"
/// snackbar.
///
/// A11y (PR #20): 44dp hit target (IconButton default), semantic button label
/// "Paylaş: {title}", focus ring + keyboard activation (inherited from
/// IconButton).
class MoproShareButton extends ConsumerWidget {
  const MoproShareButton({
    required this.url,
    required this.title,
    this.subject,
    this.padding,
    super.key,
  });

  /// Absolute URL to share.
  final String url;

  /// Short title for the share message ("{title} — {url}").
  final String title;

  /// Optional subject for share intents that support it (e.g. email).
  final String? subject;

  /// Optional padding so the button composes into existing action rows.
  final EdgeInsets? padding;

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref.read(shareServiceProvider).share(
          text: '$title — $url',
          subject: subject ?? title,
        );
    if (outcome == ShareOutcome.copiedToClipboard) {
      messenger.showSnackBar(
        SnackBar(content: Text('share.link_copied'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'share.share_a11y'.tr(namedArgs: {'title': title}),
      child: IconButton(
        onPressed: () => _onTap(context, ref),
        padding: padding ?? const EdgeInsets.all(8),
        tooltip: 'share.share'.tr(),
        icon: Icon(Icons.share_outlined, size: 24, color: cs.primary),
      ),
    );
  }
}
