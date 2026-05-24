// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_product_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateProductRequest _$CreateProductRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'CreateProductRequest',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'seller_id',
        'category_id',
        'brand',
        'default_currency',
        'default_locale',
      ],
    );
    final val = CreateProductRequest(
      sellerId: $checkedConvert('seller_id', (v) => (v as num).toInt()),
      categoryId: $checkedConvert('category_id', (v) => (v as num).toInt()),
      brand: $checkedConvert('brand', (v) => v as String),
      defaultCurrency: $checkedConvert('default_currency', (v) => v as String),
      defaultLocale: $checkedConvert('default_locale', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'sellerId': 'seller_id',
    'categoryId': 'category_id',
    'defaultCurrency': 'default_currency',
    'defaultLocale': 'default_locale',
  },
);

Map<String, dynamic> _$CreateProductRequestToJson(
  CreateProductRequest instance,
) => <String, dynamic>{
  'seller_id': instance.sellerId,
  'category_id': instance.categoryId,
  'brand': instance.brand,
  'default_currency': instance.defaultCurrency,
  'default_locale': instance.defaultLocale,
};
