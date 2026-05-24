// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seller_order_breakdown_totals.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SellerOrderBreakdownTotals _$SellerOrderBreakdownTotalsFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'SellerOrderBreakdownTotals',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'gross_minor',
        'commission_minor',
        'kdv_minor',
        'net_minor',
        'currency',
      ],
    );
    final val = SellerOrderBreakdownTotals(
      grossMinor: $checkedConvert('gross_minor', (v) => (v as num).toInt()),
      commissionMinor: $checkedConvert(
        'commission_minor',
        (v) => (v as num).toInt(),
      ),
      kdvMinor: $checkedConvert('kdv_minor', (v) => (v as num).toInt()),
      netMinor: $checkedConvert('net_minor', (v) => (v as num).toInt()),
      currency: $checkedConvert('currency', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'grossMinor': 'gross_minor',
    'commissionMinor': 'commission_minor',
    'kdvMinor': 'kdv_minor',
    'netMinor': 'net_minor',
  },
);

Map<String, dynamic> _$SellerOrderBreakdownTotalsToJson(
  SellerOrderBreakdownTotals instance,
) => <String, dynamic>{
  'gross_minor': instance.grossMinor,
  'commission_minor': instance.commissionMinor,
  'kdv_minor': instance.kdvMinor,
  'net_minor': instance.netMinor,
  'currency': instance.currency,
};
