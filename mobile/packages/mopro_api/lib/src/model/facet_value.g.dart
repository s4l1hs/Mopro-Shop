// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'facet_value.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FacetValue _$FacetValueFromJson(Map<String, dynamic> json) =>
    $checkedCreate('FacetValue', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['value', 'count']);
      final val = FacetValue(
        value: $checkedConvert('value', (v) => v as String),
        count: $checkedConvert('count', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$FacetValueToJson(FacetValue instance) =>
    <String, dynamic>{'value': instance.value, 'count': instance.count};
