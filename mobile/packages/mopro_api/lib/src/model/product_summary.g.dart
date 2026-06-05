// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductSummary _$ProductSummaryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'ProductSummary',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'seller_id',
        'category_id',
        'brand',
        'status',
        'title',
        'price_minor',
        'price_currency',
        'cashback_preview',
      ],
    );
    final val = ProductSummary(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      sellerId: $checkedConvert('seller_id', (v) => (v as num).toInt()),
      categoryId: $checkedConvert('category_id', (v) => (v as num).toInt()),
      brand: $checkedConvert('brand', (v) => v as String),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$ProductSummaryStatusEnumEnumMap, v),
      ),
      title: $checkedConvert('title', (v) => v as String),
      priceMinor: $checkedConvert('price_minor', (v) => (v as num).toInt()),
      priceCurrency: $checkedConvert('price_currency', (v) => v as String),
      coverImageUrl: $checkedConvert('cover_image_url', (v) => v as String?),
      originalPriceMinor: $checkedConvert(
        'original_price_minor',
        (v) => (v as num?)?.toInt(),
      ),
      discountPct: $checkedConvert('discount_pct', (v) => (v as num?)?.toInt()),
      ratingAvg: $checkedConvert('rating_avg', (v) => (v as num?)?.toDouble()),
      ratingCount: $checkedConvert(
        'rating_count',
        (v) => (v as num?)?.toInt() ?? 0,
      ),
      flashPriceMinor: $checkedConvert(
        'flash_price_minor',
        (v) => (v as num?)?.toInt(),
      ),
      freeShipping: $checkedConvert(
        'free_shipping',
        (v) => v as bool? ?? false,
      ),
      favoritesCount: $checkedConvert(
        'favorites_count',
        (v) => (v as num?)?.toInt() ?? 0,
      ),
      lowest30dPriceMinor: $checkedConvert(
        'lowest_30d_price_minor',
        (v) => (v as num?)?.toInt(),
      ),
      cashbackPreview: $checkedConvert(
        'cashback_preview',
        (v) => CashbackPreview.fromJson(v as Map<String, dynamic>),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'sellerId': 'seller_id',
    'categoryId': 'category_id',
    'priceMinor': 'price_minor',
    'priceCurrency': 'price_currency',
    'coverImageUrl': 'cover_image_url',
    'originalPriceMinor': 'original_price_minor',
    'discountPct': 'discount_pct',
    'ratingAvg': 'rating_avg',
    'ratingCount': 'rating_count',
    'flashPriceMinor': 'flash_price_minor',
    'freeShipping': 'free_shipping',
    'favoritesCount': 'favorites_count',
    'lowest30dPriceMinor': 'lowest_30d_price_minor',
    'cashbackPreview': 'cashback_preview',
  },
);

Map<String, dynamic> _$ProductSummaryToJson(ProductSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'seller_id': instance.sellerId,
      'category_id': instance.categoryId,
      'brand': instance.brand,
      'status': _$ProductSummaryStatusEnumEnumMap[instance.status]!,
      'title': instance.title,
      'price_minor': instance.priceMinor,
      'price_currency': instance.priceCurrency,
      'cover_image_url': ?instance.coverImageUrl,
      'original_price_minor': ?instance.originalPriceMinor,
      'discount_pct': ?instance.discountPct,
      'rating_avg': ?instance.ratingAvg,
      'rating_count': ?instance.ratingCount,
      'flash_price_minor': ?instance.flashPriceMinor,
      'free_shipping': ?instance.freeShipping,
      'favorites_count': ?instance.favoritesCount,
      'lowest_30d_price_minor': ?instance.lowest30dPriceMinor,
      'cashback_preview': instance.cashbackPreview.toJson(),
    };

const _$ProductSummaryStatusEnumEnumMap = {
  ProductSummaryStatusEnum.active: 'active',
  ProductSummaryStatusEnum.inactive: 'inactive',
  ProductSummaryStatusEnum.draft: 'draft',
};
