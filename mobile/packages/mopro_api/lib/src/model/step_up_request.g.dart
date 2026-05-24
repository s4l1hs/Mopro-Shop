// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'step_up_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StepUpRequest _$StepUpRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StepUpRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['otp_code']);
      final val = StepUpRequest(
        otpCode: $checkedConvert('otp_code', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'otpCode': 'otp_code'});

Map<String, dynamic> _$StepUpRequestToJson(StepUpRequest instance) =>
    <String, dynamic>{'otp_code': instance.otpCode};
