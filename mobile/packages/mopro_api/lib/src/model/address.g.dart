// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'address.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Address _$AddressFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Address',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'label',
        'name',
        'phone',
        'city',
        'district',
        'full_address',
        'is_default',
      ],
    );
    final val = Address(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      label: $checkedConvert('label', (v) => v as String),
      name: $checkedConvert('name', (v) => v as String),
      phone: $checkedConvert('phone', (v) => v as String),
      city: $checkedConvert('city', (v) => v as String),
      district: $checkedConvert('district', (v) => v as String),
      neighborhood: $checkedConvert('neighborhood', (v) => v as String?),
      fullAddress: $checkedConvert('full_address', (v) => v as String),
      postalCode: $checkedConvert('postal_code', (v) => v as String?),
      isDefault: $checkedConvert('is_default', (v) => v as bool),
    );
    return val;
  },
  fieldKeyMap: const {
    'fullAddress': 'full_address',
    'postalCode': 'postal_code',
    'isDefault': 'is_default',
  },
);

Map<String, dynamic> _$AddressToJson(Address instance) => <String, dynamic>{
  'id': instance.id,
  'label': instance.label,
  'name': instance.name,
  'phone': instance.phone,
  'city': instance.city,
  'district': instance.district,
  if (instance.neighborhood != null) 'neighborhood': instance.neighborhood,
  'full_address': instance.fullAddress,
  if (instance.postalCode != null) 'postal_code': instance.postalCode,
  'is_default': instance.isDefault,
};
