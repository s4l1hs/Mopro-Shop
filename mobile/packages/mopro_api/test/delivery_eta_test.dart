import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';

// tests for DeliveryEta
void main() {
  final DeliveryEta? instance = /* DeliveryEta(...) */ null;
  // TODO add properties to the entity

  group(DeliveryEta, () {
    // Lower bound of the transit business-day estimate.
    // int minDays
    test('to test the property `minDays`', () async {
      // TODO
    });

    // Upper bound of the transit business-day estimate.
    // int maxDays
    test('to test the property `maxDays`', () async {
      // TODO
    });

    // true when derived from a concrete origin×destination transit row; false when it is the conservative national fallback (unknown origin or destination, e.g. a guest with no address). 
    // bool confident
    test('to test the property `confident`', () async {
      // TODO
    });

    // Normalized key of the seller's dispatch city, for an optional \"{city}'dan gönderilir\" line. Omitted when the origin is unknown. 
    // String dispatchCity
    test('to test the property `dispatchCity`', () async {
      // TODO
    });

  });
}
