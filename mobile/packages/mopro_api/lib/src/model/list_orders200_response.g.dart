// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_orders200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListOrders200Response _$ListOrders200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListOrders200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['data', 'pagination']);
  final val = ListOrders200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    pagination: $checkedConvert(
      'pagination',
      (v) => PaginationMeta.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListOrders200ResponseToJson(
  ListOrders200Response instance,
) => <String, dynamic>{
  'data': instance.data.map((e) => e.toJson()).toList(),
  'pagination': instance.pagination.toJson(),
};
