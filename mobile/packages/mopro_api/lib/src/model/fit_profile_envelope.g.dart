// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fit_profile_envelope.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FitProfileEnvelope _$FitProfileEnvelopeFromJson(Map<String, dynamic> json) =>
    $checkedCreate('FitProfileEnvelope', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['exists']);
      final val = FitProfileEnvelope(
        exists: $checkedConvert('exists', (v) => v as bool),
        profile: $checkedConvert(
          'profile',
          (v) =>
              v == null ? null : FitProfile.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$FitProfileEnvelopeToJson(FitProfileEnvelope instance) =>
    <String, dynamic>{
      'exists': instance.exists,
      'profile': ?instance.profile?.toJson(),
    };
