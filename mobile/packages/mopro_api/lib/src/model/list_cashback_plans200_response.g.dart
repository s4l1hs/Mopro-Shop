// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_cashback_plans200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListCashbackPlans200Response _$ListCashbackPlans200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListCashbackPlans200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['data', 'pagination']);
  final val = ListCashbackPlans200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => CashbackPlan.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    pagination: $checkedConvert(
      'pagination',
      (v) => CursorPaginationMeta.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListCashbackPlans200ResponseToJson(
  ListCashbackPlans200Response instance,
) => <String, dynamic>{
  'data': instance.data.map((e) => e.toJson()).toList(),
  'pagination': instance.pagination.toJson(),
};
