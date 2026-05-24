// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_cashback_payments200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListCashbackPayments200Response _$ListCashbackPayments200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListCashbackPayments200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['data', 'pagination']);
  final val = ListCashbackPayments200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => CashbackPayment.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    pagination: $checkedConvert(
      'pagination',
      (v) => CursorPaginationMeta.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListCashbackPayments200ResponseToJson(
  ListCashbackPayments200Response instance,
) => <String, dynamic>{
  'data': instance.data.map((e) => e.toJson()).toList(),
  'pagination': instance.pagination.toJson(),
};
