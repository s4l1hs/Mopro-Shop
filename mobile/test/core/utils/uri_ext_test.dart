import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/utils/uri_ext.dart';

void main() {
  group('UriEmptyClear.clearQueryParameters', () {
    test('clears an existing query', () {
      final u = Uri.parse('/categories/42?brand=Adidas&shipping=free');
      final cleared = u.clearQueryParameters();
      expect(cleared.queryParameters, isEmpty);
      expect(cleared.path, '/categories/42');
      expect(cleared.queryParameters.containsKey('brand'), isFalse);
    });

    test('is a no-op when there is no query', () {
      final u = Uri.parse('/account/security');
      expect(identical(u.clearQueryParameters(), u), isTrue);
    });

    test('contrast: replace(queryParameters: null) does NOT clear (the bug)', () {
      final u = Uri.parse('/x?a=1');
      // ignore: avoid_redundant_argument_values
      expect(u.replace(queryParameters: null).queryParameters, isNotEmpty);
      expect(u.clearQueryParameters().queryParameters, isEmpty);
    });
  });
}
