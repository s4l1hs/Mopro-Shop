//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/cashback_preview.dart';
import 'package:json_annotation/json_annotation.dart';

part 'product_summary.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ProductSummary {
  /// Returns a new [ProductSummary] instance.
  ProductSummary({

    required  this.id,

    required  this.sellerId,

    required  this.categoryId,

    required  this.brand,

    required  this.status,

    required  this.title,

    required  this.priceMinor,

    required  this.priceCurrency,

     this.coverImageUrl,

     this.originalPriceMinor,

     this.discountPct,

     this.ratingAvg,

     this.ratingCount = 0,

     this.flashPriceMinor,

     this.freeShipping = false,

     this.favoritesCount = 0,

     this.isBestseller = false,

     this.isOfficialSeller = false,

     this.basketDiscountPct,

     this.lowest30dPriceMinor,

    required  this.cashbackPreview,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'seller_id',
    required: true,
    includeIfNull: false,
  )


  final int sellerId;



  @JsonKey(
    
    name: r'category_id',
    required: true,
    includeIfNull: false,
  )


  final int categoryId;



  @JsonKey(
    
    name: r'brand',
    required: true,
    includeIfNull: false,
  )


  final String brand;



  @JsonKey(
    
    name: r'status',
    required: true,
    includeIfNull: false,
  )


  final ProductSummaryStatusEnum status;



      /// Locale-resolved
  @JsonKey(
    
    name: r'title',
    required: true,
    includeIfNull: false,
  )


  final String title;



      /// Lowest-priced active variant price in minor units
  @JsonKey(
    
    name: r'price_minor',
    required: true,
    includeIfNull: false,
  )


  final int priceMinor;



  @JsonKey(
    
    name: r'price_currency',
    required: true,
    includeIfNull: false,
  )


  final String priceCurrency;



      /// First image URL of the lowest-priced variant
  @JsonKey(
    
    name: r'cover_image_url',
    required: false,
    includeIfNull: false,
  )


  final String? coverImageUrl;



      /// MSRP in minor units. When set and greater than price_minor, render with strikethrough; backend also emits discount_pct. 
  @JsonKey(
    
    name: r'original_price_minor',
    required: false,
    includeIfNull: false,
  )


  final int? originalPriceMinor;



      /// Server-computed discount % when original_price_minor > price_minor. Render as red %-badge next to the strikethrough. 
  @JsonKey(
    
    name: r'discount_pct',
    required: false,
    includeIfNull: false,
  )


  final int? discountPct;



      /// Average review rating (0.0–5.0); null when rating_count = 0
  @JsonKey(
    
    name: r'rating_avg',
    required: false,
    includeIfNull: false,
  )


  final double? ratingAvg;



      /// Number of reviews aggregated into rating_avg
  @JsonKey(
    defaultValue: 0,
    name: r'rating_count',
    required: false,
    includeIfNull: false,
  )


  final int? ratingCount;



      /// Flash-deal price in minor units; set only for products served by the /home/flash-deals rail. When present, render this as the price and price_minor as the strikethrough original. 
  @JsonKey(
    
    name: r'flash_price_minor',
    required: false,
    includeIfNull: false,
  )


  final int? flashPriceMinor;



      /// When true, render the \"Kargo Bedava\" (free-shipping) badge (P-009). Sourced from the products.free_shipping flag. 
  @JsonKey(
    defaultValue: false,
    name: r'free_shipping',
    required: false,
    includeIfNull: false,
  )


  final bool? freeShipping;



      /// Number of users who favorited this product — social proof by the heart on the card / PDP (P-004). Zero when none. 
  @JsonKey(
    defaultValue: 0,
    name: r'favorites_count',
    required: false,
    includeIfNull: false,
  )


  final int? favoritesCount;



      /// When true, render the \"Çok Satan\" bestseller stamp on the card (G-3). Sourced from the products.is_bestseller flag. 
  @JsonKey(
    defaultValue: false,
    name: r'is_bestseller',
    required: false,
    includeIfNull: false,
  )


  final bool? isBestseller;



      /// When true, the product's seller is official/verified — render the \"Resmi Satıcı\" badge on the card (PLP-17). App-merged per page from seller_schema (no cross-schema JOIN, §5). 
  @JsonKey(
    defaultValue: false,
    name: r'is_official_seller',
    required: false,
    includeIfNull: false,
  )


  final bool? isOfficialSeller;



      /// Extra discount percentage applied at the basket — renders the \"Sepette %X İndirim\" pill (G-3). Omitted when null (no pill). Sourced from the products.basket_discount_pct column. 
  @JsonKey(
    
    name: r'basket_discount_pct',
    required: false,
    includeIfNull: false,
  )


  final int? basketDiscountPct;



      /// Lowest price (minor units) applied in the last 30 days, for compliant display of price reductions (TR 6502 / EU Omnibus 2019/2161, P-030). Omitted when no in-window price history. The frontend shows the \"30 günün en düşük fiyatı\" line only when this is below price_minor — today it equals price_minor for every product (prices are immutable post-creation, so history has not yet diverged from the baseline). 
  @JsonKey(
    
    name: r'lowest_30d_price_minor',
    required: false,
    includeIfNull: false,
  )


  final int? lowest30dPriceMinor;



  @JsonKey(
    
    name: r'cashback_preview',
    required: true,
    includeIfNull: false,
  )


  final CashbackPreview cashbackPreview;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ProductSummary &&
      other.id == id &&
      other.sellerId == sellerId &&
      other.categoryId == categoryId &&
      other.brand == brand &&
      other.status == status &&
      other.title == title &&
      other.priceMinor == priceMinor &&
      other.priceCurrency == priceCurrency &&
      other.coverImageUrl == coverImageUrl &&
      other.originalPriceMinor == originalPriceMinor &&
      other.discountPct == discountPct &&
      other.ratingAvg == ratingAvg &&
      other.ratingCount == ratingCount &&
      other.flashPriceMinor == flashPriceMinor &&
      other.freeShipping == freeShipping &&
      other.favoritesCount == favoritesCount &&
      other.isBestseller == isBestseller &&
      other.isOfficialSeller == isOfficialSeller &&
      other.basketDiscountPct == basketDiscountPct &&
      other.lowest30dPriceMinor == lowest30dPriceMinor &&
      other.cashbackPreview == cashbackPreview;

    @override
    int get hashCode =>
        id.hashCode +
        sellerId.hashCode +
        categoryId.hashCode +
        brand.hashCode +
        status.hashCode +
        title.hashCode +
        priceMinor.hashCode +
        priceCurrency.hashCode +
        coverImageUrl.hashCode +
        originalPriceMinor.hashCode +
        discountPct.hashCode +
        ratingAvg.hashCode +
        ratingCount.hashCode +
        flashPriceMinor.hashCode +
        freeShipping.hashCode +
        favoritesCount.hashCode +
        isBestseller.hashCode +
        isOfficialSeller.hashCode +
        basketDiscountPct.hashCode +
        lowest30dPriceMinor.hashCode +
        cashbackPreview.hashCode;

  factory ProductSummary.fromJson(Map<String, dynamic> json) => _$ProductSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$ProductSummaryToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum ProductSummaryStatusEnum {
@JsonValue(r'active')
active(r'active'),
@JsonValue(r'inactive')
inactive(r'inactive'),
@JsonValue(r'draft')
draft(r'draft');

const ProductSummaryStatusEnum(this.value);

final String value;

@override
String toString() => value;
}


