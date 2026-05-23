import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/address/providers/address_form_controller.dart';

void main() {
  test('isValid is false when all fields are empty', () {
    const state = AddressFormState();
    expect(state.isValid, isFalse);
  });

  test('isValid is false when only some required fields are filled', () {
    const state = AddressFormState(
      label: 'Ev',
      name: 'Ali Veli',
      phone: '+905321234567',
      city: 'İstanbul',
    );
    expect(state.isValid, isFalse);
  });

  test('isValid is true when all required fields are filled', () {
    const state = AddressFormState(
      label: 'Ev',
      name: 'Ali Veli',
      phone: '+905321234567',
      city: 'İstanbul',
      district: 'Kadıköy',
      fullAddress: 'Test Cad. No:1',
    );
    expect(state.isValid, isTrue);
  });

  test('isValid is true with optional fields also filled', () {
    const state = AddressFormState(
      label: 'İş',
      name: 'Ayşe Demir',
      phone: '+905321112233',
      city: 'Ankara',
      district: 'Çankaya',
      neighborhood: 'Kızılay',
      fullAddress: 'Atatürk Bulvarı No:15',
      postalCode: '06100',
      isDefault: true,
    );
    expect(state.isValid, isTrue);
  });

  test('toAddressInput omits optional empty fields', () {
    const state = AddressFormState(
      label: 'Ev',
      name: 'Test',
      phone: '+905321234567',
      city: 'İzmir',
      district: 'Konak',
      fullAddress: 'Kemeraltı Cad. No:5',
    );
    final input = state.toAddressInput();
    expect(input.neighborhood, isNull);
    expect(input.postalCode, isNull);
  });

  test('toAddressInput includes optional fields when non-empty', () {
    const state = AddressFormState(
      label: 'Ev',
      name: 'Test',
      phone: '+905321234567',
      city: 'İzmir',
      district: 'Konak',
      neighborhood: 'Alsancak',
      fullAddress: 'Kemeraltı Cad. No:5',
      postalCode: '35250',
    );
    final input = state.toAddressInput();
    expect(input.neighborhood, 'Alsancak');
    expect(input.postalCode, '35250');
  });

  test('copyWith setCity resets district', () {
    const state = AddressFormState(
      city: 'İstanbul',
      district: 'Kadıköy',
    );
    final updated = state.copyWith(city: 'Ankara', district: '');
    expect(updated.city, 'Ankara');
    expect(updated.district, isEmpty);
  });
}
