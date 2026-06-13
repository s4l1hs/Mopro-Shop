// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fit_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FitProfile _$FitProfileFromJson(Map<String, dynamic> json) => $checkedCreate(
  'FitProfile',
  json,
  ($checkedConvert) {
    $checkKeys(json, requiredKeys: const ['fit_pref']);
    final val = FitProfile(
      chestMm: $checkedConvert('chest_mm', (v) => (v as num?)?.toInt()),
      waistMm: $checkedConvert('waist_mm', (v) => (v as num?)?.toInt()),
      hipMm: $checkedConvert('hip_mm', (v) => (v as num?)?.toInt()),
      inseamMm: $checkedConvert('inseam_mm', (v) => (v as num?)?.toInt()),
      heightMm: $checkedConvert('height_mm', (v) => (v as num?)?.toInt()),
      fitPref: $checkedConvert('fit_pref', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'chestMm': 'chest_mm',
    'waistMm': 'waist_mm',
    'hipMm': 'hip_mm',
    'inseamMm': 'inseam_mm',
    'heightMm': 'height_mm',
    'fitPref': 'fit_pref',
  },
);

Map<String, dynamic> _$FitProfileToJson(FitProfile instance) =>
    <String, dynamic>{
      'chest_mm': ?instance.chestMm,
      'waist_mm': ?instance.waistMm,
      'hip_mm': ?instance.hipMm,
      'inseam_mm': ?instance.inseamMm,
      'height_mm': ?instance.heightMm,
      'fit_pref': instance.fitPref,
    };
