// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seller_order_breakdown_items_inner.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SellerOrderBreakdownItemsInner _$SellerOrderBreakdownItemsInnerFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'SellerOrderBreakdownItemsInner',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'product_title',
        'quantity',
        'gross_minor',
        'commission_minor',
        'kdv_minor',
        'service_fee_minor',
        'net_minor',
        'currency',
      ],
    );
    final val = SellerOrderBreakdownItemsInner(
      productTitle: $checkedConvert('product_title', (v) => v as String),
      quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
      grossMinor: $checkedConvert('gross_minor', (v) => (v as num).toInt()),
      commissionMinor: $checkedConvert(
        'commission_minor',
        (v) => (v as num).toInt(),
      ),
      commissionPct: $checkedConvert(
        'commission_pct',
        (v) => (v as num?)?.toDouble(),
      ),
      kdvMinor: $checkedConvert('kdv_minor', (v) => (v as num).toInt()),
      serviceFeeMinor: $checkedConvert(
        'service_fee_minor',
        (v) => (v as num).toInt(),
      ),
      netMinor: $checkedConvert('net_minor', (v) => (v as num).toInt()),
      currency: $checkedConvert('currency', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'productTitle': 'product_title',
    'grossMinor': 'gross_minor',
    'commissionMinor': 'commission_minor',
    'commissionPct': 'commission_pct',
    'kdvMinor': 'kdv_minor',
    'serviceFeeMinor': 'service_fee_minor',
    'netMinor': 'net_minor',
  },
);

Map<String, dynamic> _$SellerOrderBreakdownItemsInnerToJson(
  SellerOrderBreakdownItemsInner instance,
) => <String, dynamic>{
  'product_title': instance.productTitle,
  'quantity': instance.quantity,
  'gross_minor': instance.grossMinor,
  'commission_minor': instance.commissionMinor,
  if (instance.commissionPct != null) 'commission_pct': instance.commissionPct,
  'kdv_minor': instance.kdvMinor,
  'service_fee_minor': instance.serviceFeeMinor,
  'net_minor': instance.netMinor,
  'currency': instance.currency,
};
