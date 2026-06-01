import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/growth/meta_tags_service.dart';
import 'package:mopro/features/growth/seo_head.dart';

class _RecordingMetaTagsService implements MetaTagsService {
  MetaTagsInput? last;
  int calls = 0;
  @override
  void setMetaTags(MetaTagsInput input) {
    last = input;
    calls++;
  }
}

void main() {
  group('buildMetaTagSpecs', () {
    test('emits title/description/OG/twitter; canonical + image when present', () {
      final specs = buildMetaTagSpecs(
        const MetaTagsInput(
          title: 'Ürün — Mopro',
          description: 'Açıklama',
          imageUrl: 'https://cdn/x.jpg',
          canonicalUrl: 'https://mopro.shop/products/1',
          openGraphExtras: {'og:type': 'product'},
        ),
      );
      expect(
        specs,
        containsAll(const <MetaTagSpec>[
          MetaTagSpec(MetaTagKind.title, '', 'Ürün — Mopro'),
          MetaTagSpec(MetaTagKind.metaName, 'description', 'Açıklama'),
          MetaTagSpec(MetaTagKind.metaProperty, 'og:title', 'Ürün — Mopro'),
          MetaTagSpec(MetaTagKind.metaProperty, 'og:type', 'product'),
          MetaTagSpec(MetaTagKind.metaName, 'twitter:card', 'summary_large_image'),
          MetaTagSpec(MetaTagKind.metaProperty, 'og:url', 'https://mopro.shop/products/1'),
          MetaTagSpec(MetaTagKind.linkCanonical, '', 'https://mopro.shop/products/1'),
          MetaTagSpec(MetaTagKind.metaProperty, 'og:image', 'https://cdn/x.jpg'),
          MetaTagSpec(MetaTagKind.metaName, 'twitter:image', 'https://cdn/x.jpg'),
        ]),
      );
    });

    test('omits canonical + image specs when not supplied; og:type defaults', () {
      final specs = buildMetaTagSpecs(
        const MetaTagsInput(title: 'T', description: 'D'),
      );
      expect(specs.any((s) => s.kind == MetaTagKind.linkCanonical), isFalse);
      expect(specs.any((s) => s.key == 'og:image'), isFalse);
      expect(
        specs,
        contains(const MetaTagSpec(MetaTagKind.metaProperty, 'og:type', 'website')),
      );
    });
  });

  group('seoDescription', () {
    test('collapses whitespace and truncates with ellipsis', () {
      final out = seoDescription('a    b\n\nc');
      expect(out, 'a b c');
      final long = seoDescription('x' * 200);
      expect(long.length, 160);
      expect(long.endsWith('…'), isTrue);
    });
  });

  test('default MetaTagsService is a no-op off web (does not throw)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // In the VM (dart.library.html absent) the provider yields the no-op impl.
    expect(
      () => container.read(metaTagsServiceProvider).setMetaTags(
            const MetaTagsInput(title: 'T', description: 'D'),
          ),
      returnsNormally,
    );
  });

  testWidgets('SeoHead applies meta after a frame + renders its child',
      (tester) async {
    final svc = _RecordingMetaTagsService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [metaTagsServiceProvider.overrideWithValue(svc)],
        child: const MaterialApp(
          home: SeoHead(
            meta: MetaTagsInput(
              title: 'Mağaza — Mopro',
              description: 'Bio',
              canonicalUrl: 'https://mopro.shop/sellers/acme-store',
            ),
            child: Text('CONTENT', textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget);
    expect(svc.calls, greaterThanOrEqualTo(1));
    expect(svc.last?.title, 'Mağaza — Mopro');
    expect(svc.last?.canonicalUrl, 'https://mopro.shop/sellers/acme-store');
  });
}
