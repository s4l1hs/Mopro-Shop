// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cart.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Cart _$CartFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Cart',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'user_id',
        'items',
        'subtotal_minor',
        'subtotal_currency',
        'total_monthly_coin_minor',
        'coin_currency',
      ],
    );
    final val = Cart(
      userId: $checkedConvert('user_id', (v) => (v as num).toInt()),
      items: $checkedConvert(
        'items',
        (v) => (v as List<dynamic>)
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      subtotalMinor: $checkedConvert(
        'subtotal_minor',
        (v) => (v as num).toInt(),
      ),
      subtotalCurrency: $checkedConvert(
        'subtotal_currency',
        (v) => v as String,
      ),
      totalMonthlyCoinMinor: $checkedConvert(
        'total_monthly_coin_minor',
        (v) => (v as num).toInt(),
      ),
      coinCurrency: $checkedConvert('coin_currency', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'userId': 'user_id',
    'subtotalMinor': 'subtotal_minor',
    'subtotalCurrency': 'subtotal_currency',
    'totalMonthlyCoinMinor': 'total_monthly_coin_minor',
    'coinCurrency': 'coin_currency',
  },
);

Map<String, dynamic> _$CartToJson(Cart instance) => <String, dynamic>{
  'user_id': instance.userId,
  'items': instance.items.map((e) => e.toJson()).toList(),
  'subtotal_minor': instance.subtotalMinor,
  'subtotal_currency': instance.subtotalCurrency,
  'total_monthly_coin_minor': instance.totalMonthlyCoinMinor,
  'coin_currency': instance.coinCurrency,
};
