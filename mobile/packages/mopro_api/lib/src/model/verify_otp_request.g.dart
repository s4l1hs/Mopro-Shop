// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'verify_otp_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VerifyOtpRequest _$VerifyOtpRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('VerifyOtpRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['phone', 'code']);
      final val = VerifyOtpRequest(
        phone: $checkedConvert('phone', (v) => v as String),
        code: $checkedConvert('code', (v) => v as String),
        purpose: $checkedConvert(
          'purpose',
          (v) => $enumDecodeNullable(_$VerifyOtpRequestPurposeEnumEnumMap, v),
        ),
      );
      return val;
    });

Map<String, dynamic> _$VerifyOtpRequestToJson(VerifyOtpRequest instance) =>
    <String, dynamic>{
      'phone': instance.phone,
      'code': instance.code,
      'purpose': ?_$VerifyOtpRequestPurposeEnumEnumMap[instance.purpose],
    };

const _$VerifyOtpRequestPurposeEnumEnumMap = {
  VerifyOtpRequestPurposeEnum.login: 'login',
  VerifyOtpRequestPurposeEnum.stepUp: 'step_up',
};
