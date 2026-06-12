import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';

// tests for Membership
void main() {
  final Membership? instance = /* Membership(...) */ null;
  // TODO add properties to the entity

  group(Membership, () {
    // Current tier code (e.g. classic, gold, elite).
    // String tier
    test('to test the property `tier`', () async {
      // TODO
    });

    // 1-based ladder position of the current tier.
    // int rank
    test('to test the property `rank`', () async {
      // TODO
    });

    // Rolling qualification window length in days.
    // int windowDays
    test('to test the property `windowDays`', () async {
      // TODO
    });

    // Delivered-order spend in the window, minor units.
    // int spendMinor
    test('to test the property `spendMinor`', () async {
      // TODO
    });

    // Delivered orders in the window.
    // int orderCount
    test('to test the property `orderCount`', () async {
      // TODO
    });

    // Currency of spend_minor and the thresholds.
    // String currency
    test('to test the property `currency`', () async {
      // TODO
    });

    // Next tier code; omitted at the top tier.
    // String nextTier
    test('to test the property `nextTier`', () async {
      // TODO
    });

    // Spend threshold of the next tier, minor units.
    // int nextMinSpendMinor
    test('to test the property `nextMinSpendMinor`', () async {
      // TODO
    });

    // Order-count threshold of the next tier.
    // int nextMinOrders
    test('to test the property `nextMinOrders`', () async {
      // TODO
    });

  });
}
