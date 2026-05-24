// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'return_request_items_inner.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReturnRequestItemsInner _$ReturnRequestItemsInnerFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'ReturnRequestItemsInner',
  json,
  ($checkedConvert) {
    $checkKeys(json, requiredKeys: const ['order_item_id', 'quantity']);
    final val = ReturnRequestItemsInner(
      orderItemId: $checkedConvert('order_item_id', (v) => (v as num).toInt()),
      quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
    );
    return val;
  },
  fieldKeyMap: const {'orderItemId': 'order_item_id'},
);

Map<String, dynamic> _$ReturnRequestItemsInnerToJson(
  ReturnRequestItemsInner instance,
) => <String, dynamic>{
  'order_item_id': instance.orderItemId,
  'quantity': instance.quantity,
};
