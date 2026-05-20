import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for WalletApi
void main() {
  final instance = MoproApi().getWalletApi();

  group(WalletApi, () {
    // Get the authenticated user's coin wallet balance
    //
    //Future<WalletBalance> getWalletBalance({ String xTraceId, String currency }) async
    test('test getWalletBalance', () async {
      // TODO
    });

    // List wallet transaction history (cursor-paginated)
    //
    //Future<ListWalletTransactions200Response> listWalletTransactions({ String xTraceId, String cursor, int limit }) async
    test('test listWalletTransactions', () async {
      // TODO
    });

  });
}
