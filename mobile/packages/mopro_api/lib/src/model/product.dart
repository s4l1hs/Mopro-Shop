//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/variant.dart';
import 'package:mopro_api/src/model/cashback_preview.dart';
import 'package:json_annotation/json_annotation.dart';

part 'product.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Product {
  /// Returns a new [Product] instance.
  Product({

    required  this.id,

    required  this.sellerId,

    required  this.sellerName,

    required  this.categoryId,

    required  this.brand,

    required  this.status,

    required  this.title,

    required  this.description,

    required  this.variants,

    required  this.cashbackPreview,

    required  this.createdAt,
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
    
    name: r'seller_name',
    required: true,
    includeIfNull: false,
  )


  final String sellerName;



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


  final ProductStatusEnum status;



      /// Locale-resolved from Accept-Language header
  @JsonKey(
    
    name: r'title',
    required: true,
    includeIfNull: false,
  )


  final String title;



      /// Locale-resolved. Falls back to tr-TR if requested locale unavailable.
  @JsonKey(
    
    name: r'description',
    required: true,
    includeIfNull: false,
  )


  final String description;



  @JsonKey(
    
    name: r'variants',
    required: true,
    includeIfNull: false,
  )


  final List<Variant> variants;



  @JsonKey(
    
    name: r'cashback_preview',
    required: true,
    includeIfNull: false,
  )


  final CashbackPreview cashbackPreview;



  @JsonKey(
    
    name: r'created_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime createdAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Product &&
      other.id == id &&
      other.sellerId == sellerId &&
      other.sellerName == sellerName &&
      other.categoryId == categoryId &&
      other.brand == brand &&
      other.status == status &&
      other.title == title &&
      other.description == description &&
      other.variants == variants &&
      other.cashbackPreview == cashbackPreview &&
      other.createdAt == createdAt;

    @override
    int get hashCode =>
        id.hashCode +
        sellerId.hashCode +
        sellerName.hashCode +
        categoryId.hashCode +
        brand.hashCode +
        status.hashCode +
        title.hashCode +
        description.hashCode +
        variants.hashCode +
        cashbackPreview.hashCode +
        createdAt.hashCode;

  factory Product.fromJson(Map<String, dynamic> json) => _$ProductFromJson(json);

  Map<String, dynamic> toJson() => _$ProductToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum ProductStatusEnum {
@JsonValue(r'active')
active(r'active'),
@JsonValue(r'inactive')
inactive(r'inactive'),
@JsonValue(r'draft')
draft(r'draft');

const ProductStatusEnum(this.value);

final String value;

@override
String toString() => value;
}


