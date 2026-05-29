// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_me_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateMeRequest _$UpdateMeRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'UpdateMeRequest',
      json,
      ($checkedConvert) {
        final val = UpdateMeRequest(
          nameFirst: $checkedConvert('name_first', (v) => v as String?),
          nameLast: $checkedConvert('name_last', (v) => v as String?),
          email: $checkedConvert('email', (v) => v as String?),
          locale: $checkedConvert('locale', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {'nameFirst': 'name_first', 'nameLast': 'name_last'},
    );

Map<String, dynamic> _$UpdateMeRequestToJson(UpdateMeRequest instance) =>
    <String, dynamic>{
      'name_first': ?instance.nameFirst,
      'name_last': ?instance.nameLast,
      'email': ?instance.email,
      'locale': ?instance.locale,
    };
