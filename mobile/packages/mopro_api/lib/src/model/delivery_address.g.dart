// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delivery_address.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeliveryAddress _$DeliveryAddressFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'DeliveryAddress',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'recipient_name',
            'full_address',
            'district',
            'city',
          ],
        );
        final val = DeliveryAddress(
          label: $checkedConvert('label', (v) => v as String?),
          recipientName: $checkedConvert('recipient_name', (v) => v as String),
          phone: $checkedConvert('phone', (v) => v as String?),
          fullAddress: $checkedConvert('full_address', (v) => v as String),
          neighborhood: $checkedConvert('neighborhood', (v) => v as String?),
          district: $checkedConvert('district', (v) => v as String),
          city: $checkedConvert('city', (v) => v as String),
          postalCode: $checkedConvert('postal_code', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {
        'recipientName': 'recipient_name',
        'fullAddress': 'full_address',
        'postalCode': 'postal_code',
      },
    );

Map<String, dynamic> _$DeliveryAddressToJson(DeliveryAddress instance) =>
    <String, dynamic>{
      'label': ?instance.label,
      'recipient_name': instance.recipientName,
      'phone': ?instance.phone,
      'full_address': instance.fullAddress,
      'neighborhood': ?instance.neighborhood,
      'district': instance.district,
      'city': instance.city,
      'postal_code': ?instance.postalCode,
    };
