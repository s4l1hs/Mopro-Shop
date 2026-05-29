// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cashback_payment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CashbackPayment _$CashbackPaymentFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CashbackPayment',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'id',
            'plan_id',
            'period_yyyymm',
            'amount_minor',
            'currency',
            'status',
          ],
        );
        final val = CashbackPayment(
          id: $checkedConvert('id', (v) => (v as num).toInt()),
          planId: $checkedConvert('plan_id', (v) => (v as num).toInt()),
          periodYyyymm: $checkedConvert('period_yyyymm', (v) => v as String),
          amountMinor: $checkedConvert(
            'amount_minor',
            (v) => (v as num).toInt(),
          ),
          currency: $checkedConvert('currency', (v) => v as String),
          status: $checkedConvert(
            'status',
            (v) => $enumDecode(_$CashbackPaymentStatusEnumEnumMap, v),
          ),
          paidAt: $checkedConvert(
            'paid_at',
            (v) => v == null ? null : DateTime.parse(v as String),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'planId': 'plan_id',
        'periodYyyymm': 'period_yyyymm',
        'amountMinor': 'amount_minor',
        'paidAt': 'paid_at',
      },
    );

Map<String, dynamic> _$CashbackPaymentToJson(CashbackPayment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'plan_id': instance.planId,
      'period_yyyymm': instance.periodYyyymm,
      'amount_minor': instance.amountMinor,
      'currency': instance.currency,
      'status': _$CashbackPaymentStatusEnumEnumMap[instance.status]!,
      'paid_at': ?instance.paidAt?.toIso8601String(),
    };

const _$CashbackPaymentStatusEnumEnumMap = {
  CashbackPaymentStatusEnum.scheduled: 'scheduled',
  CashbackPaymentStatusEnum.paid: 'paid',
  CashbackPaymentStatusEnum.failed: 'failed',
};
