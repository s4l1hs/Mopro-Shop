// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrderItem _$OrderItemFromJson(Map<String, dynamic> json) => $checkedCreate(
  'OrderItem',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'variant_id',
        'product_id',
        'title',
        'quantity',
        'price_minor',
        'price_currency',
        'commission_pct_bps',
      ],
    );
    final val = OrderItem(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      variantId: $checkedConvert('variant_id', (v) => (v as num).toInt()),
      productId: $checkedConvert('product_id', (v) => (v as num).toInt()),
      title: $checkedConvert('title', (v) => v as String),
      quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
      priceMinor: $checkedConvert('price_minor', (v) => (v as num).toInt()),
      priceCurrency: $checkedConvert('price_currency', (v) => v as String),
      commissionPctBps: $checkedConvert(
        'commission_pct_bps',
        (v) => (v as num).toInt(),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'variantId': 'variant_id',
    'productId': 'product_id',
    'priceMinor': 'price_minor',
    'priceCurrency': 'price_currency',
    'commissionPctBps': 'commission_pct_bps',
  },
);

Map<String, dynamic> _$OrderItemToJson(OrderItem instance) => <String, dynamic>{
  'id': instance.id,
  'variant_id': instance.variantId,
  'product_id': instance.productId,
  'title': instance.title,
  'quantity': instance.quantity,
  'price_minor': instance.priceMinor,
  'price_currency': instance.priceCurrency,
  'commission_pct_bps': instance.commissionPctBps,
};
