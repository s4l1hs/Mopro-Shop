import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:uuid/uuid.dart';

class AddressFormState {
  const AddressFormState({
    this.label = '',
    this.name = '',
    this.phone = '',
    this.city = '',
    this.district = '',
    this.neighborhood = '',
    this.fullAddress = '',
    this.postalCode = '',
    this.isDefault = false,
    this.submitting = false,
    this.error,
  });

  final String label;
  final String name;
  final String phone;
  final String city;
  final String district;
  final String neighborhood;
  final String fullAddress;
  final String postalCode;
  final bool isDefault;
  final bool submitting;
  final AppError? error;

  bool get isValid =>
      label.isNotEmpty &&
      name.isNotEmpty &&
      phone.isNotEmpty &&
      city.isNotEmpty &&
      district.isNotEmpty &&
      fullAddress.isNotEmpty;

  AddressFormState copyWith({
    String? label,
    String? name,
    String? phone,
    String? city,
    String? district,
    String? neighborhood,
    String? fullAddress,
    String? postalCode,
    bool? isDefault,
    bool? submitting,
    AppError? error,
    bool clearError = false,
  }) =>
      AddressFormState(
        label: label ?? this.label,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        city: city ?? this.city,
        district: district ?? this.district,
        neighborhood: neighborhood ?? this.neighborhood,
        fullAddress: fullAddress ?? this.fullAddress,
        postalCode: postalCode ?? this.postalCode,
        isDefault: isDefault ?? this.isDefault,
        submitting: submitting ?? this.submitting,
        error: clearError ? null : error ?? this.error,
      );

  AddressInput toAddressInput() => AddressInput(
        label: label,
        name: name,
        phone: phone,
        city: city,
        district: district,
        neighborhood: neighborhood.isEmpty ? null : neighborhood,
        fullAddress: fullAddress,
        postalCode: postalCode.isEmpty ? null : postalCode,
        isDefault: isDefault,
      );
}

final addressFormProvider = NotifierProviderFamily<AddressFormController,
    AddressFormState, int?>(AddressFormController.new);

class AddressFormController
    extends FamilyNotifier<AddressFormState, int?> {
  @override
  AddressFormState build(int? arg) => const AddressFormState();

  void prefill(Address address) {
    state = state.copyWith(
      label: address.label,
      name: address.name,
      phone: address.phone,
      city: address.city,
      district: address.district,
      neighborhood: address.neighborhood ?? '',
      fullAddress: address.fullAddress,
      postalCode: address.postalCode ?? '',
      isDefault: address.isDefault,
    );
  }

  void setLabel(String v) => state = state.copyWith(label: v, clearError: true);
  void setName(String v) => state = state.copyWith(name: v, clearError: true);
  void setPhone(String v) => state = state.copyWith(phone: v, clearError: true);
  void setCity(String v) =>
      state = state.copyWith(city: v, district: '', clearError: true);
  void setDistrict(String v) =>
      state = state.copyWith(district: v, clearError: true);
  void setNeighborhood(String v) =>
      state = state.copyWith(neighborhood: v, clearError: true);
  void setFullAddress(String v) =>
      state = state.copyWith(fullAddress: v, clearError: true);
  void setPostalCode(String v) =>
      state = state.copyWith(postalCode: v, clearError: true);
  // ignore: avoid_positional_boolean_parameters — simple setter mirrors copyWith
  void setIsDefault(bool v) => state = state.copyWith(isDefault: v);

  Future<Address?> submit() async {
    if (!state.isValid) return null;
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(addressApiProvider);
      final idempotencyKey = const Uuid().v4();
      final input = state.toAddressInput();
      Response<Address> resp;
      final editId = arg;
      if (editId != null) {
        resp = await api.updateAddress(
          xIdempotencyKey: idempotencyKey,
          id: editId,
          addressInput: input,
        );
      } else {
        resp = await api.createAddress(
          xIdempotencyKey: idempotencyKey,
          addressInput: input,
        );
      }
      state = state.copyWith(submitting: false);
      return resp.data;
    } on DioException catch (e) {
      final err = e.error;
      state = state.copyWith(
        submitting: false,
        error: err is AppError ? err : NetworkError(message: e.message ?? ''),
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        submitting: false,
        error: UnknownError(statusCode: 0, message: e.toString()),
      );
      return null;
    }
  }
}
