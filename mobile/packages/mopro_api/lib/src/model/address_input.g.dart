// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'address_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AddressInput _$AddressInputFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'AddressInput',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'label',
            'name',
            'phone',
            'city',
            'district',
            'full_address',
          ],
        );
        final val = AddressInput(
          label: $checkedConvert('label', (v) => v as String),
          name: $checkedConvert('name', (v) => v as String),
          phone: $checkedConvert('phone', (v) => v as String),
          city: $checkedConvert('city', (v) => v as String),
          district: $checkedConvert('district', (v) => v as String),
          neighborhood: $checkedConvert('neighborhood', (v) => v as String?),
          fullAddress: $checkedConvert('full_address', (v) => v as String),
          postalCode: $checkedConvert('postal_code', (v) => v as String?),
          isDefault: $checkedConvert('is_default', (v) => v as bool? ?? false),
        );
        return val;
      },
      fieldKeyMap: const {
        'fullAddress': 'full_address',
        'postalCode': 'postal_code',
        'isDefault': 'is_default',
      },
    );

Map<String, dynamic> _$AddressInputToJson(AddressInput instance) =>
    <String, dynamic>{
      'label': instance.label,
      'name': instance.name,
      'phone': instance.phone,
      'city': instance.city,
      'district': instance.district,
      'neighborhood': ?instance.neighborhood,
      'full_address': instance.fullAddress,
      'postal_code': ?instance.postalCode,
      'is_default': ?instance.isDefault,
    };
