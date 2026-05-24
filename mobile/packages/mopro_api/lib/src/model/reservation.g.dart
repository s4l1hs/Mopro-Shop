// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reservation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Reservation _$ReservationFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Reservation', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['id', 'expires_at']);
      final val = Reservation(
        id: $checkedConvert('id', (v) => v as String),
        expiresAt: $checkedConvert(
          'expires_at',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    }, fieldKeyMap: const {'expiresAt': 'expires_at'});

Map<String, dynamic> _$ReservationToJson(Reservation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'expires_at': instance.expiresAt.toIso8601String(),
    };
