import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';

// tests for CashbackPlan
void main() {
  final CashbackPlan? instance = /* CashbackPlan(...) */ null;
  // TODO add properties to the entity

  group(CashbackPlan, () {
    // int id
    test('to test the property `id`', () async {
      // TODO
    });

    // int orderId
    test('to test the property `orderId`', () async {
      // TODO
    });

    // int productId
    test('to test the property `productId`', () async {
      // TODO
    });

    // String productTitle
    test('to test the property `productTitle`', () async {
      // TODO
    });

    // String productImageUrl
    test('to test the property `productImageUrl`', () async {
      // TODO
    });

    // int monthlyAmountMinor
    test('to test the property `monthlyAmountMinor`', () async {
      // TODO
    });

    // String currency
    test('to test the property `currency`', () async {
      // TODO
    });

    // String status
    test('to test the property `status`', () async {
      // TODO
    });

    // ISO 8601 date (YYYY-MM-DD). First instalment paid on or after this date.
    // DateTime startDate
    test('to test the property `startDate`', () async {
      // TODO
    });

    // Reference rate in basis points (5000 = 50%). Frozen at plan creation time per the v6 perpetual cashback formula. Existing plans retain their original rate even if the platform's reference rate changes later. See LEDGER_GUIDE.md §3.4 for the formula derivation. 
    // int referenceInterestRateBps
    test('to test the property `referenceInterestRateBps`', () async {
      // TODO
    });

    // DateTime createdAt
    test('to test the property `createdAt`', () async {
      // TODO
    });

  });
}
