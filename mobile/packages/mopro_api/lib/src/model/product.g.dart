// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Product _$ProductFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Product',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'seller_id',
        'seller_name',
        'category_id',
        'brand',
        'status',
        'title',
        'description',
        'variants',
        'attributes',
        'cashback_preview',
        'created_at',
      ],
    );
    final val = Product(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      sellerId: $checkedConvert('seller_id', (v) => (v as num).toInt()),
      sellerName: $checkedConvert('seller_name', (v) => v as String),
      sellerSlug: $checkedConvert('seller_slug', (v) => v as String?),
      categoryId: $checkedConvert('category_id', (v) => (v as num).toInt()),
      brand: $checkedConvert('brand', (v) => v as String),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$ProductStatusEnumEnumMap, v),
      ),
      title: $checkedConvert('title', (v) => v as String),
      description: $checkedConvert('description', (v) => v as String),
      variants: $checkedConvert(
        'variants',
        (v) => (v as List<dynamic>)
            .map((e) => Variant.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      attributes: $checkedConvert(
        'attributes',
        (v) => (v as List<dynamic>)
            .map((e) => ProductAttribute.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      cashbackPreview: $checkedConvert(
        'cashback_preview',
        (v) => CashbackPreview.fromJson(v as Map<String, dynamic>),
      ),
      deliveryEta: $checkedConvert(
        'delivery_eta',
        (v) =>
            v == null ? null : DeliveryEta.fromJson(v as Map<String, dynamic>),
      ),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'sellerId': 'seller_id',
    'sellerName': 'seller_name',
    'sellerSlug': 'seller_slug',
    'categoryId': 'category_id',
    'cashbackPreview': 'cashback_preview',
    'deliveryEta': 'delivery_eta',
    'createdAt': 'created_at',
  },
);

Map<String, dynamic> _$ProductToJson(Product instance) => <String, dynamic>{
  'id': instance.id,
  'seller_id': instance.sellerId,
  'seller_name': instance.sellerName,
  'seller_slug': ?instance.sellerSlug,
  'category_id': instance.categoryId,
  'brand': instance.brand,
  'status': _$ProductStatusEnumEnumMap[instance.status]!,
  'title': instance.title,
  'description': instance.description,
  'variants': instance.variants.map((e) => e.toJson()).toList(),
  'attributes': instance.attributes.map((e) => e.toJson()).toList(),
  'cashback_preview': instance.cashbackPreview.toJson(),
  'delivery_eta': ?instance.deliveryEta?.toJson(),
  'created_at': instance.createdAt.toIso8601String(),
};

const _$ProductStatusEnumEnumMap = {
  ProductStatusEnum.active: 'active',
  ProductStatusEnum.inactive: 'inactive',
  ProductStatusEnum.draft: 'draft',
};
