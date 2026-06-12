// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Membership _$MembershipFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Membership',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'tier',
        'rank',
        'window_days',
        'spend_minor',
        'order_count',
        'currency',
      ],
    );
    final val = Membership(
      tier: $checkedConvert('tier', (v) => v as String),
      rank: $checkedConvert('rank', (v) => (v as num).toInt()),
      windowDays: $checkedConvert('window_days', (v) => (v as num).toInt()),
      spendMinor: $checkedConvert('spend_minor', (v) => (v as num).toInt()),
      orderCount: $checkedConvert('order_count', (v) => (v as num).toInt()),
      currency: $checkedConvert('currency', (v) => v as String),
      nextTier: $checkedConvert('next_tier', (v) => v as String?),
      nextMinSpendMinor: $checkedConvert(
        'next_min_spend_minor',
        (v) => (v as num?)?.toInt(),
      ),
      nextMinOrders: $checkedConvert(
        'next_min_orders',
        (v) => (v as num?)?.toInt(),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'windowDays': 'window_days',
    'spendMinor': 'spend_minor',
    'orderCount': 'order_count',
    'nextTier': 'next_tier',
    'nextMinSpendMinor': 'next_min_spend_minor',
    'nextMinOrders': 'next_min_orders',
  },
);

Map<String, dynamic> _$MembershipToJson(Membership instance) =>
    <String, dynamic>{
      'tier': instance.tier,
      'rank': instance.rank,
      'window_days': instance.windowDays,
      'spend_minor': instance.spendMinor,
      'order_count': instance.orderCount,
      'currency': instance.currency,
      'next_tier': ?instance.nextTier,
      'next_min_spend_minor': ?instance.nextMinSpendMinor,
      'next_min_orders': ?instance.nextMinOrders,
    };
