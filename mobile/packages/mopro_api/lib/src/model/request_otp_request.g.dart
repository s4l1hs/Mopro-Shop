// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_otp_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RequestOtpRequest _$RequestOtpRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RequestOtpRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['phone']);
      final val = RequestOtpRequest(
        phone: $checkedConvert('phone', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$RequestOtpRequestToJson(RequestOtpRequest instance) =>
    <String, dynamic>{'phone': instance.phone};
