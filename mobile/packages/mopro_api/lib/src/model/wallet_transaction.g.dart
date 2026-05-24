// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wallet_transaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WalletTransaction _$WalletTransactionFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'WalletTransaction',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'type',
        'amount_minor',
        'currency',
        'occurred_at',
      ],
    );
    final val = WalletTransaction(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      type: $checkedConvert(
        'type',
        (v) => $enumDecode(_$WalletTransactionTypeEnumEnumMap, v),
      ),
      amountMinor: $checkedConvert('amount_minor', (v) => (v as num).toInt()),
      currency: $checkedConvert('currency', (v) => v as String),
      description: $checkedConvert('description', (v) => v as String?),
      referenceId: $checkedConvert('reference_id', (v) => (v as num?)?.toInt()),
      referenceType: $checkedConvert(
        'reference_type',
        (v) =>
            $enumDecodeNullable(_$WalletTransactionReferenceTypeEnumEnumMap, v),
      ),
      occurredAt: $checkedConvert(
        'occurred_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'amountMinor': 'amount_minor',
    'referenceId': 'reference_id',
    'referenceType': 'reference_type',
    'occurredAt': 'occurred_at',
  },
);

Map<String, dynamic> _$WalletTransactionToJson(WalletTransaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': _$WalletTransactionTypeEnumEnumMap[instance.type]!,
      'amount_minor': instance.amountMinor,
      'currency': instance.currency,
      'description': ?instance.description,
      'reference_id': ?instance.referenceId,
      'reference_type':
          ?_$WalletTransactionReferenceTypeEnumEnumMap[instance.referenceType],
      'occurred_at': instance.occurredAt.toIso8601String(),
    };

const _$WalletTransactionTypeEnumEnumMap = {
  WalletTransactionTypeEnum.credit: 'credit',
  WalletTransactionTypeEnum.debit: 'debit',
};

const _$WalletTransactionReferenceTypeEnumEnumMap = {
  WalletTransactionReferenceTypeEnum.cashbackPayment: 'cashback_payment',
  WalletTransactionReferenceTypeEnum.payout: 'payout',
  WalletTransactionReferenceTypeEnum.adjustment: 'adjustment',
};
