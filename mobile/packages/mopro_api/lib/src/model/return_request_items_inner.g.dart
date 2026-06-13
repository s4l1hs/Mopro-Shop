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
      reason: $checkedConvert(
        'reason',
        (v) =>
            $enumDecodeNullable(_$ReturnRequestItemsInnerReasonEnumEnumMap, v),
      ),
      note: $checkedConvert('note', (v) => v as String?),
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
  'reason': ?_$ReturnRequestItemsInnerReasonEnumEnumMap[instance.reason],
  'note': ?instance.note,
};

const _$ReturnRequestItemsInnerReasonEnumEnumMap = {
  ReturnRequestItemsInnerReasonEnum.wrongProduct: 'wrong_product',
  ReturnRequestItemsInnerReasonEnum.notAsDescribed: 'not_as_described',
  ReturnRequestItemsInnerReasonEnum.damaged: 'damaged',
  ReturnRequestItemsInnerReasonEnum.sizeIssue: 'size_issue',
  ReturnRequestItemsInnerReasonEnum.changedMind: 'changed_mind',
  ReturnRequestItemsInnerReasonEnum.other: 'other',
};
