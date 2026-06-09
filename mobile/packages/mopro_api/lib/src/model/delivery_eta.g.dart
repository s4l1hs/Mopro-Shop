// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delivery_eta.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeliveryEta _$DeliveryEtaFromJson(Map<String, dynamic> json) => $checkedCreate(
  'DeliveryEta',
  json,
  ($checkedConvert) {
    $checkKeys(json, requiredKeys: const ['min_days', 'max_days', 'confident']);
    final val = DeliveryEta(
      minDays: $checkedConvert('min_days', (v) => (v as num).toInt()),
      maxDays: $checkedConvert('max_days', (v) => (v as num).toInt()),
      confident: $checkedConvert('confident', (v) => v as bool),
      dispatchCity: $checkedConvert('dispatch_city', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {
    'minDays': 'min_days',
    'maxDays': 'max_days',
    'dispatchCity': 'dispatch_city',
  },
);

Map<String, dynamic> _$DeliveryEtaToJson(DeliveryEta instance) =>
    <String, dynamic>{
      'min_days': instance.minDays,
      'max_days': instance.maxDays,
      'confident': instance.confident,
      'dispatch_city': ?instance.dispatchCity,
    };
