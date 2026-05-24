// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Device _$DeviceFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Device',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'fcm_token',
        'device_model',
        'os_version',
        'created_at',
      ],
    );
    final val = Device(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      fcmToken: $checkedConvert('fcm_token', (v) => v as String),
      deviceModel: $checkedConvert('device_model', (v) => v as String),
      osVersion: $checkedConvert('os_version', (v) => v as String),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'fcmToken': 'fcm_token',
    'deviceModel': 'device_model',
    'osVersion': 'os_version',
    'createdAt': 'created_at',
  },
);

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'id': instance.id,
  'fcm_token': instance.fcmToken,
  'device_model': instance.deviceModel,
  'os_version': instance.osVersion,
  'created_at': instance.createdAt.toIso8601String(),
};
