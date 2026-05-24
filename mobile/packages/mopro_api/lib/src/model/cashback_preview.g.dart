// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cashback_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CashbackPreview _$CashbackPreviewFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CashbackPreview',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const ['monthly_coin_minor', 'currency'],
        );
        final val = CashbackPreview(
          monthlyCoinMinor: $checkedConvert(
            'monthly_coin_minor',
            (v) => (v as num).toInt(),
          ),
          currency: $checkedConvert('currency', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'monthlyCoinMinor': 'monthly_coin_minor'},
    );

Map<String, dynamic> _$CashbackPreviewToJson(CashbackPreview instance) =>
    <String, dynamic>{
      'monthly_coin_minor': instance.monthlyCoinMinor,
      'currency': instance.currency,
    };
