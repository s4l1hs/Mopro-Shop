// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_envelope.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ErrorEnvelope _$ErrorEnvelopeFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ErrorEnvelope', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['error']);
      final val = ErrorEnvelope(
        error: $checkedConvert(
          'error',
          (v) => ErrorEnvelopeError.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ErrorEnvelopeToJson(ErrorEnvelope instance) =>
    <String, dynamic>{'error': instance.error.toJson()};
