// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_order_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateOrderRequest _$CreateOrderRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateOrderRequest',
      json,
      ($checkedConvert) {
        $checkKeys(json, requiredKeys: const ['reservation_id', 'address_id']);
        final val = CreateOrderRequest(
          reservationId: $checkedConvert('reservation_id', (v) => v as String),
          addressId: $checkedConvert('address_id', (v) => (v as num).toInt()),
        );
        return val;
      },
      fieldKeyMap: const {
        'reservationId': 'reservation_id',
        'addressId': 'address_id',
      },
    );

Map<String, dynamic> _$CreateOrderRequestToJson(CreateOrderRequest instance) =>
    <String, dynamic>{
      'reservation_id': instance.reservationId,
      'address_id': instance.addressId,
    };
