import 'package:flutter/foundation.dart';
import 'package:mopro/features/growth/meta_tags_service.dart';
import 'package:web/web.dart' as web;

/// Web impl: mutates `document.head` per route via package:web. Idempotent —
/// existing tags are updated in place, missing ones created. Failures never
/// propagate (defensive layering): SEO is non-essential to the user surface.
class _WebMetaTagsService implements MetaTagsService {
  @override
  void setMetaTags(MetaTagsInput input) {
    try {
      for (final spec in buildMetaTagSpecs(input)) {
        switch (spec.kind) {
          case MetaTagKind.title:
            web.document.title = spec.content;
          case MetaTagKind.metaName:
            _upsertAttr('meta', 'name', spec.key, 'content', spec.content);
          case MetaTagKind.metaProperty:
            _upsertAttr('meta', 'property', spec.key, 'content', spec.content);
          case MetaTagKind.linkCanonical:
            _upsertAttr('link', 'rel', 'canonical', 'href', spec.content);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MetaTagsService(web): $e');
    }
  }

  /// Finds `<tag matchAttr="matchVal">` in head and sets valueAttr=value, or
  /// creates the element if absent.
  void _upsertAttr(
    String tag,
    String matchAttr,
    String matchVal,
    String valueAttr,
    String value,
  ) {
    final head = web.document.head;
    if (head == null) return;
    final existing = head.querySelector('$tag[$matchAttr="$matchVal"]');
    if (existing != null) {
      existing.setAttribute(valueAttr, value);
      return;
    }
    final el = web.document.createElement(tag)
      ..setAttribute(matchAttr, matchVal)
      ..setAttribute(valueAttr, value);
    head.appendChild(el);
  }
}

MetaTagsService createMetaTagsService() => _WebMetaTagsService();
