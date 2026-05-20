import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for AddressApi
void main() {
  final instance = MoproApi().getAddressApi();

  group(AddressApi, () {
    // Add a new delivery address
    //
    //Future<Address> createAddress(String xIdempotencyKey, AddressInput addressInput, { String xTraceId }) async
    test('test createAddress', () async {
      // TODO
    });

    // Delete an address
    //
    //Future deleteAddress(String xIdempotencyKey, int id, { String xTraceId }) async
    test('test deleteAddress', () async {
      // TODO
    });

    // List the authenticated user's delivery addresses
    //
    //Future<ListAddresses200Response> listAddresses({ String xTraceId }) async
    test('test listAddresses', () async {
      // TODO
    });

    // Update an existing address
    //
    //Future<Address> updateAddress(String xIdempotencyKey, int id, AddressInput addressInput, { String xTraceId }) async
    test('test updateAddress', () async {
      // TODO
    });

  });
}
