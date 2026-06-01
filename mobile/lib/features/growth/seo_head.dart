import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/growth/meta_tags_service.dart';

/// Transparent wrapper that applies per-route SEO head content as a side effect
/// and renders [child] unchanged. Place it around the data-resolved subtree of a
/// public screen (PDP, category, help article, seller storefront) so [meta] is
/// populated from loaded data.
///
/// No-op on non-web platforms (the underlying services no-op there). Applied in
/// a post-frame callback so it never blocks first paint, and re-applied when the
/// inputs change (idempotent on the service side).
class SeoHead extends ConsumerStatefulWidget {
  const SeoHead({
    required this.meta,
    required this.child,
    super.key,
  });

  final MetaTagsInput meta;
  final Widget child;

  @override
  ConsumerState<SeoHead> createState() => _SeoHeadState();
}

class _SeoHeadState extends ConsumerState<SeoHead> {
  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(SeoHead oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-apply when the title/description/canonical change (e.g. locale switch
    // or late data). Cheap identity check on the salient fields.
    final a = oldWidget.meta;
    final b = widget.meta;
    if (a.title != b.title ||
        a.description != b.description ||
        a.canonicalUrl != b.canonicalUrl ||
        a.imageUrl != b.imageUrl) {
      _apply();
    }
  }

  void _apply() {
    final meta = widget.meta;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(metaTagsServiceProvider).setMetaTags(meta);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Truncates [text] to [max] characters for meta descriptions (default 160).
String seoDescription(String text, {int max = 160}) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= max) return clean;
  return '${clean.substring(0, max - 1).trimRight()}…';
}
