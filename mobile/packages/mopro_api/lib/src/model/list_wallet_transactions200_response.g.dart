// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_wallet_transactions200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListWalletTransactions200Response _$ListWalletTransactions200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListWalletTransactions200Response', json, (
  $checkedConvert,
) {
  $checkKeys(json, requiredKeys: const ['data', 'pagination']);
  final val = ListWalletTransactions200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    pagination: $checkedConvert(
      'pagination',
      (v) => CursorPaginationMeta.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListWalletTransactions200ResponseToJson(
  ListWalletTransactions200Response instance,
) => <String, dynamic>{
  'data': instance.data.map((e) => e.toJson()).toList(),
  'pagination': instance.pagination.toJson(),
};
