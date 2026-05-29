// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Category _$CategoryFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Category',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const ['id', 'name', 'slug', 'commission_pct_bps'],
    );
    final val = Category(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      name: $checkedConvert('name', (v) => v as String),
      slug: $checkedConvert('slug', (v) => v as String),
      parentId: $checkedConvert('parent_id', (v) => (v as num?)?.toInt()),
      iconUrl: $checkedConvert('icon_url', (v) => v as String?),
      commissionPctBps: $checkedConvert(
        'commission_pct_bps',
        (v) => (v as num).toInt(),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'parentId': 'parent_id',
    'iconUrl': 'icon_url',
    'commissionPctBps': 'commission_pct_bps',
  },
);

Map<String, dynamic> _$CategoryToJson(Category instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'slug': instance.slug,
  'parent_id': ?instance.parentId,
  'icon_url': ?instance.iconUrl,
  'commission_pct_bps': instance.commissionPctBps,
};
