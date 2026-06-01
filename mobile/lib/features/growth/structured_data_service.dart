import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mopro/features/growth/structured_data_service_noop.dart'
    if (dart.library.html) 'package:mopro/features/growth/structured_data_service_web.dart';

/// Sets a single JSON-LD payload for the current route, written as a
/// `<script type="application/ld+json">` in the head (replacing any existing
/// one). No-op on non-web platforms.
abstract class StructuredDataService {
  void setJsonLd(Map<String, dynamic> data);
}

final structuredDataServiceProvider =
    Provider<StructuredDataService>((_) => createStructuredDataService());

// ── Per-route schema builders (pure; schema.org shapes) ───────────────────────

String _money(int minor) => (minor / 100).toStringAsFixed(2);

/// schema.org/Product with an Offer (and optional AggregateRating).
Map<String, dynamic> productJsonLd({
  required String name,
  required String description,
  required String url,
  String? image,
  String? brand,
  int? priceMinor,
  String? priceCurrency,
  double? ratingAvg,
  int? ratingCount,
}) {
  final data = <String, dynamic>{
    '@context': 'https://schema.org',
    '@type': 'Product',
    'name': name,
    'description': description,
    'url': url,
  };
  if (image != null && image.isNotEmpty) data['image'] = image;
  if (brand != null && brand.isNotEmpty) {
    data['brand'] = {'@type': 'Brand', 'name': brand};
  }
  if (priceMinor != null && priceCurrency != null) {
    data['offers'] = {
      '@type': 'Offer',
      'price': _money(priceMinor),
      'priceCurrency': priceCurrency,
      'availability': 'https://schema.org/InStock',
      'url': url,
    };
  }
  if (ratingAvg != null && ratingCount != null && ratingCount > 0) {
    data['aggregateRating'] = {
      '@type': 'AggregateRating',
      'ratingValue': ratingAvg.toStringAsFixed(1),
      'reviewCount': ratingCount,
    };
  }
  return data;
}

/// schema.org/BreadcrumbList from ordered (name, url) items.
Map<String, dynamic> breadcrumbJsonLd(List<({String name, String url})> items) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    'itemListElement': [
      for (var i = 0; i < items.length; i++)
        {
          '@type': 'ListItem',
          'position': i + 1,
          'name': items[i].name,
          'item': items[i].url,
        },
    ],
  };
}

/// schema.org/Article (Mopro help articles are markdown, not FAQ-structured).
Map<String, dynamic> articleJsonLd({
  required String headline,
  required String url,
}) {
  return {
    '@context': 'https://schema.org',
    '@type': 'Article',
    'headline': headline,
    'url': url,
  };
}

/// schema.org/Organization for a seller storefront.
Map<String, dynamic> organizationJsonLd({
  required String name,
  required String url,
  String? logo,
}) {
  final data = <String, dynamic>{
    '@context': 'https://schema.org',
    '@type': 'Organization',
    'name': name,
    'url': url,
  };
  if (logo != null && logo.isNotEmpty) data['logo'] = logo;
  return data;
}
