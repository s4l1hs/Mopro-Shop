import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/growth/structured_data_service.dart';

void main() {
  group('productJsonLd', () {
    test('includes Product type, offer, brand, aggregateRating', () {
      final data = productJsonLd(
        name: 'Çok Seçenekli Ürün',
        description: 'Açıklama',
        url: 'https://mopro.shop/products/1',
        image: 'https://cdn/x.jpg',
        brand: 'Acme',
        priceMinor: 12900,
        priceCurrency: 'TRY',
        ratingAvg: 4.5,
        ratingCount: 12,
      );
      expect(data['@context'], 'https://schema.org');
      expect(data['@type'], 'Product');
      expect(data['name'], 'Çok Seçenekli Ürün');
      expect(data['image'], 'https://cdn/x.jpg');
      expect((data['brand'] as Map)['name'], 'Acme');
      final offer = data['offers'] as Map<String, dynamic>;
      expect(offer['@type'], 'Offer');
      expect(offer['price'], '129.00'); // minor → decimal
      expect(offer['priceCurrency'], 'TRY');
      expect(offer['availability'], 'https://schema.org/InStock');
      final rating = data['aggregateRating'] as Map<String, dynamic>;
      expect(rating['ratingValue'], '4.5');
      expect(rating['reviewCount'], 12);
      // JSON round-trips (serializable).
      expect(jsonDecode(jsonEncode(data)), equals(data));
    });

    test('omits offer + aggregateRating when absent', () {
      final data = productJsonLd(
        name: 'T',
        description: 'D',
        url: 'https://mopro.shop/products/2',
      );
      expect(data.containsKey('offers'), isFalse);
      expect(data.containsKey('aggregateRating'), isFalse);
      expect(data.containsKey('brand'), isFalse);
    });
  });

  test('breadcrumbJsonLd numbers positions from 1', () {
    final data = breadcrumbJsonLd([
      (name: 'Mopro', url: 'https://mopro.shop'),
      (name: 'Elektronik', url: 'https://mopro.shop/categories/30'),
    ]);
    expect(data['@type'], 'BreadcrumbList');
    final items = data['itemListElement'] as List;
    expect(items, hasLength(2));
    expect((items[0] as Map)['position'], 1);
    expect((items[1] as Map)['position'], 2);
    expect((items[1] as Map)['name'], 'Elektronik');
    expect(jsonDecode(jsonEncode(data)), equals(data));
  });

  test('articleJsonLd + organizationJsonLd shapes', () {
    final article =
        articleJsonLd(headline: 'Şifre sıfırlama', url: 'https://mopro.shop/help/article/reset');
    expect(article['@type'], 'Article');
    expect(article['headline'], 'Şifre sıfırlama');

    final org = organizationJsonLd(
      name: 'Acme Store',
      url: 'https://mopro.shop/sellers/acme-store',
      logo: 'https://cdn/logo.png',
    );
    expect(org['@type'], 'Organization');
    expect(org['name'], 'Acme Store');
    expect(org['logo'], 'https://cdn/logo.png');
    final orgNoLogo = organizationJsonLd(name: 'X', url: 'https://mopro.shop/sellers/x');
    expect(orgNoLogo.containsKey('logo'), isFalse);
  });

  test('default StructuredDataService is a no-op off web', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container
          .read(structuredDataServiceProvider)
          .setJsonLd({'@type': 'Product'}),
      returnsNormally,
    );
  });
}
