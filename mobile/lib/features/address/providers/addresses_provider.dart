
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';

class AddressesState {
  const AddressesState({
    this.addresses = const AsyncLoading(),
  });

  final AsyncValue<List<Address>> addresses;

  AddressesState copyWith({AsyncValue<List<Address>>? addresses}) =>
      AddressesState(addresses: addresses ?? this.addresses);
}

final addressesProvider =
    NotifierProvider<AddressesNotifier, AddressesState>(AddressesNotifier.new);

class AddressesNotifier extends Notifier<AddressesState> {
  @override
  AddressesState build() {
    Future<void>.microtask(_load);
    return const AddressesState();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    state = state.copyWith(addresses: const AsyncLoading());
    try {
      final api = ref.read(addressApiProvider);
      final resp = await api.listAddresses();
      state = state.copyWith(
        addresses: AsyncData(resp.data?.data ?? []),
      );
    } on DioException catch (e, st) {
      final err = e.error;
      state = state.copyWith(
        addresses: AsyncError(
          err is AppError ? err : NetworkError(message: e.message ?? ''),
          st,
        ),
      );
    } catch (e, st) {
      state = state.copyWith(
        addresses: AsyncError(
          UnknownError(statusCode: 0, message: e.toString()),
          st,
        ),
      );
    }
  }

  Future<bool> deleteAddress(int id) async {
    try {
      final api = ref.read(addressApiProvider);
      await api.deleteAddress(
        xIdempotencyKey: 'del-addr-$id-${DateTime.now().millisecondsSinceEpoch}',
        id: id,
      );
      final current = state.addresses.valueOrNull ?? [];
      state = state.copyWith(
        addresses: AsyncData(current.where((a) => a.id != id).toList()),
      );
      return true;
    } on DioException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}
