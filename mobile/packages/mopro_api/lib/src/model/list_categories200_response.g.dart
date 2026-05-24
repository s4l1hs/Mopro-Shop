// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_categories200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListCategories200Response _$ListCategories200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListCategories200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['data']);
  final val = ListCategories200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListCategories200ResponseToJson(
  ListCategories200Response instance,
) => <String, dynamic>{'data': instance.data.map((e) => e.toJson()).toList()};
