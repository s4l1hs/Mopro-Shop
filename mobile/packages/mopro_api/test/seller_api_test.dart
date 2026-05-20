import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for SellerApi
void main() {
  final instance = MoproApi().getSellerApi();

  group(SellerApi, () {
    // Seller transparency breakdown for a specific order
    //
    // Returns per-item commission, KDV, service fee (always 0 for Mopro), and net payout amounts. Used by the seller panel web app.  **Current auth:** Requires `X-Mopro-Seller-Id` header containing the seller's integer ID. Phase 4.2a replaces this with seller JWT (`bearerAuth`). 
    //
    //Future<SellerOrderBreakdown> getSellerOrderBreakdown(int id, String xMoproSellerId, { String xTraceId }) async
    test('test getSellerOrderBreakdown', () async {
      // TODO
    });

  });
}
