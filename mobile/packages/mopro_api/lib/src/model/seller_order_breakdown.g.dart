// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seller_order_breakdown.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SellerOrderBreakdown _$SellerOrderBreakdownFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'SellerOrderBreakdown',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const ['order_id', 'items', 'totals', 'unlock_at'],
    );
    final val = SellerOrderBreakdown(
      orderId: $checkedConvert('order_id', (v) => (v as num).toInt()),
      items: $checkedConvert(
        'items',
        (v) => (v as List<dynamic>)
            .map(
              (e) => SellerOrderBreakdownItemsInner.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      totals: $checkedConvert(
        'totals',
        (v) => SellerOrderBreakdownTotals.fromJson(v as Map<String, dynamic>),
      ),
      unlockAt: $checkedConvert(
        'unlock_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {'orderId': 'order_id', 'unlockAt': 'unlock_at'},
);

Map<String, dynamic> _$SellerOrderBreakdownToJson(
  SellerOrderBreakdown instance,
) => <String, dynamic>{
  'order_id': instance.orderId,
  'items': instance.items.map((e) => e.toJson()).toList(),
  'totals': instance.totals.toJson(),
  'unlock_at': instance.unlockAt.toIso8601String(),
};
