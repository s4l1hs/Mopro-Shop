// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_envelope_error.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ErrorEnvelopeError _$ErrorEnvelopeErrorFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ErrorEnvelopeError', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['code', 'message', 'trace_id']);
      final val = ErrorEnvelopeError(
        code: $checkedConvert('code', (v) => v as String),
        message: $checkedConvert('message', (v) => v as String),
        traceId: $checkedConvert('trace_id', (v) => v as String),
        fields: $checkedConvert(
          'fields',
          (v) => (v as List<dynamic>?)
              ?.map((e) => FieldError.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    }, fieldKeyMap: const {'traceId': 'trace_id'});

Map<String, dynamic> _$ErrorEnvelopeErrorToJson(ErrorEnvelopeError instance) =>
    <String, dynamic>{
      'code': instance.code,
      'message': instance.message,
      'trace_id': instance.traceId,
      if (instance.fields?.map((e) => e.toJson()).toList() != null) 'fields': instance.fields?.map((e) => e.toJson()).toList(),
    };
