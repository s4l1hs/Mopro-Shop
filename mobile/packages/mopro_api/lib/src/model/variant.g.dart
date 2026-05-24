// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'variant.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Variant _$VariantFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Variant',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'sku',
        'price_minor',
        'price_currency',
        'stock',
        'image_urls',
      ],
    );
    final val = Variant(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      sku: $checkedConvert('sku', (v) => v as String),
      color: $checkedConvert('color', (v) => v as String?),
      size: $checkedConvert('size', (v) => v as String?),
      priceMinor: $checkedConvert('price_minor', (v) => (v as num).toInt()),
      priceCurrency: $checkedConvert('price_currency', (v) => v as String),
      stock: $checkedConvert('stock', (v) => (v as num).toInt()),
      imageUrls: $checkedConvert(
        'image_urls',
        (v) => (v as List<dynamic>).map((e) => e as String).toList(),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'priceMinor': 'price_minor',
    'priceCurrency': 'price_currency',
    'imageUrls': 'image_urls',
  },
);

Map<String, dynamic> _$VariantToJson(Variant instance) => <String, dynamic>{
  'id': instance.id,
  'sku': instance.sku,
  if (instance.color != null) 'color': instance.color,
  if (instance.size != null) 'size': instance.size,
  'price_minor': instance.priceMinor,
  'price_currency': instance.priceCurrency,
  'stock': instance.stock,
  'image_urls': instance.imageUrls,
};
