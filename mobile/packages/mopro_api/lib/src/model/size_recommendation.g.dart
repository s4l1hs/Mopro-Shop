// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'size_recommendation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SizeRecommendation _$SizeRecommendationFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'SizeRecommendation',
      json,
      ($checkedConvert) {
        $checkKeys(json, requiredKeys: const ['status', 'chart_approximate']);
        final val = SizeRecommendation(
          status: $checkedConvert('status', (v) => v as String),
          garmentType: $checkedConvert('garment_type', (v) => v as String?),
          size: $checkedConvert('size', (v) => v as String?),
          signal: $checkedConvert('signal', (v) => v as String?),
          betweenLower: $checkedConvert('between_lower', (v) => v as String?),
          betweenUpper: $checkedConvert('between_upper', (v) => v as String?),
          missing: $checkedConvert(
            'missing',
            (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
          ),
          confidence: $checkedConvert('confidence', (v) => v as String?),
          estimated: $checkedConvert(
            'estimated',
            (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
          ),
          chartApproximate: $checkedConvert(
            'chart_approximate',
            (v) => v as bool,
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'garmentType': 'garment_type',
        'betweenLower': 'between_lower',
        'betweenUpper': 'between_upper',
        'chartApproximate': 'chart_approximate',
      },
    );

Map<String, dynamic> _$SizeRecommendationToJson(SizeRecommendation instance) =>
    <String, dynamic>{
      'status': instance.status,
      'garment_type': ?instance.garmentType,
      'size': ?instance.size,
      'signal': ?instance.signal,
      'between_lower': ?instance.betweenLower,
      'between_upper': ?instance.betweenUpper,
      'missing': ?instance.missing,
      'confidence': ?instance.confidence,
      'estimated': ?instance.estimated,
      'chart_approximate': instance.chartApproximate,
    };
