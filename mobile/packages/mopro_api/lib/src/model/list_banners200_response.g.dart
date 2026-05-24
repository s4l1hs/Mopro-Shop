// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_banners200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListBanners200Response _$ListBanners200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListBanners200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['data']);
  final val = ListBanners200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => Banner.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListBanners200ResponseToJson(
  ListBanners200Response instance,
) => <String, dynamic>{'data': instance.data.map((e) => e.toJson()).toList()};
