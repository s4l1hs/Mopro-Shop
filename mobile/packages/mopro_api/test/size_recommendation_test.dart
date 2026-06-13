import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';

// tests for SizeRecommendation
void main() {
  final SizeRecommendation? instance = /* SizeRecommendation(...) */ null;
  // TODO add properties to the entity

  group(SizeRecommendation, () {
    // ok | no_profile | incomplete_profile | no_chart
    // String status
    test('to test the property `status`', () async {
      // TODO
    });

    // top | bottom | dress | skirt | outerwear (chart key).
    // String garmentType
    test('to test the property `garmentType`', () async {
      // TODO
    });

    // String size
    test('to test the property `size`', () async {
      // TODO
    });

    // true_to_size | between | size_up | size_down
    // String signal
    test('to test the property `signal`', () async {
      // TODO
    });

    // String betweenLower
    test('to test the property `betweenLower`', () async {
      // TODO
    });

    // String betweenUpper
    test('to test the property `betweenUpper`', () async {
      // TODO
    });

    // List<String> missing
    test('to test the property `missing`', () async {
      // TODO
    });

    // bool chartApproximate
    test('to test the property `chartApproximate`', () async {
      // TODO
    });

  });
}
