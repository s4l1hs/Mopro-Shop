// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'step_up_token_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StepUpTokenResponse _$StepUpTokenResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'StepUpTokenResponse',
      json,
      ($checkedConvert) {
        $checkKeys(json, requiredKeys: const ['step_up_token', 'expires_in']);
        final val = StepUpTokenResponse(
          stepUpToken: $checkedConvert('step_up_token', (v) => v as String),
          expiresIn: $checkedConvert('expires_in', (v) => (v as num).toInt()),
        );
        return val;
      },
      fieldKeyMap: const {
        'stepUpToken': 'step_up_token',
        'expiresIn': 'expires_in',
      },
    );

Map<String, dynamic> _$StepUpTokenResponseToJson(
  StepUpTokenResponse instance,
) => <String, dynamic>{
  'step_up_token': instance.stepUpToken,
  'expires_in': instance.expiresIn,
};
