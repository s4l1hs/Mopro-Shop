// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => $checkedCreate(
  'User',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const ['id', 'phone', 'locale', 'created_at', 'updated_at'],
    );
    final val = User(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      phone: $checkedConvert('phone', (v) => v as String),
      nameFirst: $checkedConvert('name_first', (v) => v as String?),
      nameLast: $checkedConvert('name_last', (v) => v as String?),
      email: $checkedConvert('email', (v) => v as String?),
      locale: $checkedConvert('locale', (v) => v as String),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
      updatedAt: $checkedConvert(
        'updated_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'nameFirst': 'name_first',
    'nameLast': 'name_last',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'phone': instance.phone,
  'name_first': ?instance.nameFirst,
  'name_last': ?instance.nameLast,
  'email': ?instance.email,
  'locale': instance.locale,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
};
