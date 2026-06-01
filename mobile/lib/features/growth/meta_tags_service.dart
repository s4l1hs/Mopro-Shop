import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mopro/features/growth/meta_tags_service_noop.dart'
    if (dart.library.html) 'package:mopro/features/growth/meta_tags_service_web.dart';

/// Inputs for the per-route head meta tags.
class MetaTagsInput {
  const MetaTagsInput({
    required this.title,
    required this.description,
    this.imageUrl,
    this.canonicalUrl,
    this.openGraphExtras,
  });

  final String title;
  final String description;
  final String? imageUrl;
  final String? canonicalUrl;
  final Map<String, String>? openGraphExtras;
}

/// One head tag to apply. The web impl maps these to `document.head` elements;
/// the no-op impl ignores them. Kept as a pure value so the mapping is unit
/// testable without a DOM.
enum MetaTagKind { title, metaName, metaProperty, linkCanonical }

@immutable
class MetaTagSpec {
  const MetaTagSpec(this.kind, this.key, this.content);
  final MetaTagKind kind;

  /// For metaName/metaProperty: the name/property value (e.g. "og:title").
  /// Empty for title + canonical.
  final String key;
  final String content;

  @override
  bool operator ==(Object other) =>
      other is MetaTagSpec &&
      other.kind == kind &&
      other.key == key &&
      other.content == content;

  @override
  int get hashCode => Object.hash(kind, key, content);

  @override
  String toString() => 'MetaTagSpec(${kind.name}, "$key", "$content")';
}

/// Pure mapping from inputs to the set of head tags to apply. Shared by the web
/// impl + tests (the actual DOM write is a thin loop over this list).
List<MetaTagSpec> buildMetaTagSpecs(MetaTagsInput i) {
  final ogType = i.openGraphExtras?['og:type'] ?? 'website';
  final specs = <MetaTagSpec>[
    MetaTagSpec(MetaTagKind.title, '', i.title),
    MetaTagSpec(MetaTagKind.metaName, 'description', i.description),
    MetaTagSpec(MetaTagKind.metaProperty, 'og:title', i.title),
    MetaTagSpec(MetaTagKind.metaProperty, 'og:description', i.description),
    MetaTagSpec(MetaTagKind.metaProperty, 'og:type', ogType),
    const MetaTagSpec(
      MetaTagKind.metaName,
      'twitter:card',
      'summary_large_image',
    ),
    MetaTagSpec(MetaTagKind.metaName, 'twitter:title', i.title),
    MetaTagSpec(MetaTagKind.metaName, 'twitter:description', i.description),
  ];
  if (i.canonicalUrl != null && i.canonicalUrl!.isNotEmpty) {
    specs
      ..add(MetaTagSpec(MetaTagKind.metaProperty, 'og:url', i.canonicalUrl!))
      ..add(MetaTagSpec(MetaTagKind.linkCanonical, '', i.canonicalUrl!));
  }
  if (i.imageUrl != null && i.imageUrl!.isNotEmpty) {
    specs
      ..add(MetaTagSpec(MetaTagKind.metaProperty, 'og:image', i.imageUrl!))
      ..add(MetaTagSpec(MetaTagKind.metaName, 'twitter:image', i.imageUrl!));
  }
  // Any remaining OG extras (besides og:type, already applied).
  i.openGraphExtras?.forEach((k, v) {
    if (k != 'og:type') specs.add(MetaTagSpec(MetaTagKind.metaProperty, k, v));
  });
  return specs;
}

/// Sets per-route head meta tags. No-op on non-web platforms. Idempotent:
/// calling twice on the same route yields the same head state.
abstract class MetaTagsService {
  void setMetaTags(MetaTagsInput input);
}

/// Provided by the conditional import: a DOM-mutating impl on web, a no-op
/// elsewhere.
final metaTagsServiceProvider =
    Provider<MetaTagsService>((_) => createMetaTagsService());
