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


