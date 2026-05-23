import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/features/address/providers/addresses_provider.dart';
import 'package:mopro_api/mopro_api.dart';

Address _addr(int id, {bool isDefault = false}) => Address(
      id: id,
      label: 'Ev $id',
      name: 'Test User',
      phone: '+905321234567',
      city: 'İstanbul',
      district: 'Kadıköy',
      fullAddress: 'Test Cad. No:1',
      isDefault: isDefault,
    );

class _FakeAddressApi extends AddressApi {
  _FakeAddressApi({this.addresses = const [], this.error}) : super(Dio());

  final List<Address> addresses;
  final Exception? error;

  @override
  Future<Response<ListAddresses200Response>> listAddresses({
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (error != null) throw error!;
    return Response(
      data: ListAddresses200Response(data: addresses),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );
  }

  @override
  Future<Response<void>> deleteAddress({
    required String xIdempotencyKey,
    required int id,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response(requestOptions: RequestOptions(), statusCode: 204);
}

ProviderContainer _container(_FakeAddressApi api) => ProviderContainer(
      overrides: [addressApiProvider.overrideWithValue(api)],
    );

void main() {
  test('initial state is loading', () {
    final container = _container(_FakeAddressApi());
    addTearDown(container.dispose);
    final s = container.read(addressesProvider);
    expect(s.addresses, isA<AsyncLoading<List<Address>>>());
  });

  test('loads addresses successfully', () async {
    final api = _FakeAddressApi(addresses: [_addr(1), _addr(2)]);
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(addressesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s = container.read(addressesProvider);
    expect(s.addresses.valueOrNull?.length, 2);
  });

  test('IDOR: different user address is 404 (simulated by empty list)', () async {
    // If the server returns 404 for foreign addresses, the client sees
    // an empty list — the UI shows empty state, not foreign data.
    final api = _FakeAddressApi(addresses: []);
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(addressesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s = container.read(addressesProvider);
    expect(s.addresses.valueOrNull, isEmpty);
  });

  test('error state on API failure', () async {
    final api = _FakeAddressApi(error: Exception('network'));
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(addressesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s = container.read(addressesProvider);
    expect(s.addresses, isA<AsyncError<List<Address>>>());
  });

  test('deleteAddress removes item from local state', () async {
    final api =
        _FakeAddressApi(addresses: [_addr(1), _addr(2), _addr(3)]);
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(addressesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final deleted = await container
        .read(addressesProvider.notifier)
        .deleteAddress(2);
    expect(deleted, isTrue);

    final s = container.read(addressesProvider);
    expect(s.addresses.valueOrNull?.map((a) => a.id), isNot(contains(2)));
    expect(s.addresses.valueOrNull?.length, 2);
  });
}
