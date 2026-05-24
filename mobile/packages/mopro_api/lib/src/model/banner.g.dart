// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'banner.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Banner _$BannerFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Banner',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const ['id', 'placement', 'image_url', 'action_type'],
    );
    final val = Banner(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      placement: $checkedConvert('placement', (v) => v as String),
      imageUrl: $checkedConvert('image_url', (v) => v as String),
      actionType: $checkedConvert(
        'action_type',
        (v) => $enumDecode(_$BannerActionTypeEnumEnumMap, v),
      ),
      actionUrl: $checkedConvert('action_url', (v) => v as String?),
      expiresAt: $checkedConvert(
        'expires_at',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'imageUrl': 'image_url',
    'actionType': 'action_type',
    'actionUrl': 'action_url',
    'expiresAt': 'expires_at',
  },
);

Map<String, dynamic> _$BannerToJson(Banner instance) => <String, dynamic>{
  'id': instance.id,
  'placement': instance.placement,
  'image_url': instance.imageUrl,
  'action_type': _$BannerActionTypeEnumEnumMap[instance.actionType]!,
  'action_url': ?instance.actionUrl,
  'expires_at': ?instance.expiresAt?.toIso8601String(),
};

const _$BannerActionTypeEnumEnumMap = {
  BannerActionTypeEnum.deeplink: 'deeplink',
  BannerActionTypeEnum.external_: 'external',
  BannerActionTypeEnum.none: 'none',
};
