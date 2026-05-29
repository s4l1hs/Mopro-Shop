import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/responsive/responsive_image_url.dart';

void main() {
  String w(String url) => Uri.parse(url).queryParameters['w']!;

  group('responsiveImageUrl bucketing', () {
    test('rounds physical width to nearest 100', () {
      // DPR 1 → physical == logical.
      expect(w(responsiveImageUrl('http://x/i', targetWidthLogical: 149, devicePixelRatio: 1)), '100');
      expect(w(responsiveImageUrl('http://x/i', targetWidthLogical: 150, devicePixelRatio: 1)), '200');
      expect(w(responsiveImageUrl('http://x/i', targetWidthLogical: 151, devicePixelRatio: 1)), '200');
      // 312 and 315 both bucket to 300 (cache-friendly).
      expect(w(responsiveImageUrl('http://x/i', targetWidthLogical: 312, devicePixelRatio: 1)), '300');
      expect(w(responsiveImageUrl('http://x/i', targetWidthLogical: 315, devicePixelRatio: 1)), '300');
    });

    test('applies device pixel ratio', () {
      // 300 logical × 2.0 DPR = 600 physical → w=600.
      expect(w(responsiveImageUrl('http://x/i', targetWidthLogical: 300, devicePixelRatio: 2)), '600');
    });

    test('clamps to [100, 2000]', () {
      expect(w(responsiveImageUrl('http://x/i', targetWidthLogical: 1, devicePixelRatio: 1)), '100');
      expect(w(responsiveImageUrl('http://x/i', targetWidthLogical: 9999, devicePixelRatio: 3)), '2000');
    });

    test('preserves existing query params', () {
      final out = responsiveImageUrl(
        'http://x/i?fmt=webp&q=80',
        targetWidthLogical: 200,
        devicePixelRatio: 1,
      );
      final params = Uri.parse(out).queryParameters;
      expect(params['fmt'], 'webp');
      expect(params['q'], '80');
      expect(params['w'], '200');
    });

    test('is idempotent on a URL that already has w=', () {
      final once =
          responsiveImageUrl('http://x/i?w=999', targetWidthLogical: 200, devicePixelRatio: 1);
      final twice =
          responsiveImageUrl(once, targetWidthLogical: 200, devicePixelRatio: 1);
      expect(once, twice);
      expect(w(once), '200');
    });
  });
}
