// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cashback_plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CashbackPlan _$CashbackPlanFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CashbackPlan',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'id',
            'order_id',
            'product_id',
            'product_title',
            'monthly_amount_minor',
            'currency',
            'status',
            'start_date',
            'reference_interest_rate_bps',
            'created_at',
          ],
        );
        final val = CashbackPlan(
          id: $checkedConvert('id', (v) => (v as num).toInt()),
          orderId: $checkedConvert('order_id', (v) => (v as num).toInt()),
          productId: $checkedConvert('product_id', (v) => (v as num).toInt()),
          productTitle: $checkedConvert('product_title', (v) => v as String),
          productImageUrl: $checkedConvert(
            'product_image_url',
            (v) => v as String?,
          ),
          monthlyAmountMinor: $checkedConvert(
            'monthly_amount_minor',
            (v) => (v as num).toInt(),
          ),
          currency: $checkedConvert('currency', (v) => v as String),
          status: $checkedConvert(
            'status',
            (v) => $enumDecode(_$CashbackPlanStatusEnumEnumMap, v),
          ),
          startDate: $checkedConvert(
            'start_date',
            (v) => DateTime.parse(v as String),
          ),
          referenceInterestRateBps: $checkedConvert(
            'reference_interest_rate_bps',
            (v) => (v as num).toInt(),
          ),
          createdAt: $checkedConvert(
            'created_at',
            (v) => DateTime.parse(v as String),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'orderId': 'order_id',
        'productId': 'product_id',
        'productTitle': 'product_title',
        'productImageUrl': 'product_image_url',
        'monthlyAmountMinor': 'monthly_amount_minor',
        'startDate': 'start_date',
        'referenceInterestRateBps': 'reference_interest_rate_bps',
        'createdAt': 'created_at',
      },
    );

Map<String, dynamic> _$CashbackPlanToJson(CashbackPlan instance) =>
    <String, dynamic>{
      'id': instance.id,
      'order_id': instance.orderId,
      'product_id': instance.productId,
      'product_title': instance.productTitle,
      if (instance.productImageUrl != null) 'product_image_url': instance.productImageUrl,
      'monthly_amount_minor': instance.monthlyAmountMinor,
      'currency': instance.currency,
      'status': _$CashbackPlanStatusEnumEnumMap[instance.status]!,
      'start_date': instance.startDate.toIso8601String(),
      'reference_interest_rate_bps': instance.referenceInterestRateBps,
      'created_at': instance.createdAt.toIso8601String(),
    };

const _$CashbackPlanStatusEnumEnumMap = {
  CashbackPlanStatusEnum.active: 'active',
  CashbackPlanStatusEnum.cancelled: 'cancelled',
  CashbackPlanStatusEnum.suspended: 'suspended',
};
