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
      weightG: $checkedConvert('weight_g', (v) => (v as num?)?.toInt()),
      gender: $checkedConvert('gender', (v) => v as String?),
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
    'weightG': 'weight_g',
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
      'weight_g': ?instance.weightG,
      'gender': ?instance.gender,
      'fit_pref': instance.fitPref,
    };
