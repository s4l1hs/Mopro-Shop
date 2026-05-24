// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'field_error.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FieldError _$FieldErrorFromJson(Map<String, dynamic> json) =>
    $checkedCreate('FieldError', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['name', 'message']);
      final val = FieldError(
        name: $checkedConvert('name', (v) => v as String),
        message: $checkedConvert('message', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$FieldErrorToJson(FieldError instance) =>
    <String, dynamic>{'name': instance.name, 'message': instance.message};
