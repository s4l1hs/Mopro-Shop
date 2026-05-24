// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release_cart_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReleaseCartRequest _$ReleaseCartRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReleaseCartRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['reservation_id']);
      final val = ReleaseCartRequest(
        reservationId: $checkedConvert('reservation_id', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'reservationId': 'reservation_id'});

Map<String, dynamic> _$ReleaseCartRequestToJson(ReleaseCartRequest instance) =>
    <String, dynamic>{'reservation_id': instance.reservationId};
