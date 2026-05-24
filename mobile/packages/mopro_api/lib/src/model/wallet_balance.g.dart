// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wallet_balance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WalletBalance _$WalletBalanceFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'WalletBalance',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const ['currency', 'amount_minor', 'last_updated_at'],
        );
        final val = WalletBalance(
          currency: $checkedConvert('currency', (v) => v as String),
          amountMinor: $checkedConvert(
            'amount_minor',
            (v) => (v as num).toInt(),
          ),
          lastUpdatedAt: $checkedConvert(
            'last_updated_at',
            (v) => DateTime.parse(v as String),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'amountMinor': 'amount_minor',
        'lastUpdatedAt': 'last_updated_at',
      },
    );

Map<String, dynamic> _$WalletBalanceToJson(WalletBalance instance) =>
    <String, dynamic>{
      'currency': instance.currency,
      'amount_minor': instance.amountMinor,
      'last_updated_at': instance.lastUpdatedAt.toIso8601String(),
    };
