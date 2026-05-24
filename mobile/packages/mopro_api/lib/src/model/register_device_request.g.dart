// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_device_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RegisterDeviceRequest _$RegisterDeviceRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'RegisterDeviceRequest',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const ['fcm_token', 'device_model', 'os_version'],
    );
    final val = RegisterDeviceRequest(
      fcmToken: $checkedConvert('fcm_token', (v) => v as String),
      deviceModel: $checkedConvert('device_model', (v) => v as String),
      osVersion: $checkedConvert('os_version', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'fcmToken': 'fcm_token',
    'deviceModel': 'device_model',
    'osVersion': 'os_version',
  },
);

Map<String, dynamic> _$RegisterDeviceRequestToJson(
  RegisterDeviceRequest instance,
) => <String, dynamic>{
  'fcm_token': instance.fcmToken,
  'device_model': instance.deviceModel,
  'os_version': instance.osVersion,
};
