// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cart_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CartItem _$CartItemFromJson(Map<String, dynamic> json) => $checkedCreate(
  'CartItem',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'variant_id',
        'product_id',
        'title',
        'price_minor',
        'price_currency',
        'quantity',
        'monthly_coin_minor',
        'coin_currency',
      ],
    );
    final val = CartItem(
      variantId: $checkedConvert('variant_id', (v) => (v as num).toInt()),
      productId: $checkedConvert('product_id', (v) => (v as num).toInt()),
      title: $checkedConvert('title', (v) => v as String),
      imageUrl: $checkedConvert('image_url', (v) => v as String?),
      color: $checkedConvert('color', (v) => v as String?),
      size: $checkedConvert('size', (v) => v as String?),
      priceMinor: $checkedConvert('price_minor', (v) => (v as num).toInt()),
      priceCurrency: $checkedConvert('price_currency', (v) => v as String),
      quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
      monthlyCoinMinor: $checkedConvert(
        'monthly_coin_minor',
        (v) => (v as num).toInt(),
      ),
      coinCurrency: $checkedConvert('coin_currency', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'variantId': 'variant_id',
    'productId': 'product_id',
    'imageUrl': 'image_url',
    'priceMinor': 'price_minor',
    'priceCurrency': 'price_currency',
    'monthlyCoinMinor': 'monthly_coin_minor',
    'coinCurrency': 'coin_currency',
  },
);

Map<String, dynamic> _$CartItemToJson(CartItem instance) => <String, dynamic>{
  'variant_id': instance.variantId,
  'product_id': instance.productId,
  'title': instance.title,
  if (instance.imageUrl != null) 'image_url': instance.imageUrl,
  if (instance.color != null) 'color': instance.color,
  if (instance.size != null) 'size': instance.size,
  'price_minor': instance.priceMinor,
  'price_currency': instance.priceCurrency,
  'quantity': instance.quantity,
  'monthly_coin_minor': instance.monthlyCoinMinor,
  'coin_currency': instance.coinCurrency,
};
