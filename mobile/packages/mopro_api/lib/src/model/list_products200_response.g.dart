// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_products200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListProducts200Response _$ListProducts200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListProducts200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['data', 'pagination']);
  final val = ListProducts200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => ProductSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    pagination: $checkedConvert(
      'pagination',
      (v) => PaginationMeta.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListProducts200ResponseToJson(
  ListProducts200Response instance,
) => <String, dynamic>{
  'data': instance.data.map((e) => e.toJson()).toList(),
  'pagination': instance.pagination.toJson(),
};
