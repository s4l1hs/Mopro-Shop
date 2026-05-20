//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'create_product_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CreateProductRequest {
  /// Returns a new [CreateProductRequest] instance.
  CreateProductRequest({

    required  this.sellerId,

    required  this.categoryId,

    required  this.brand,

    required  this.defaultCurrency,

    required  this.defaultLocale,
  });

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
    
    name: r'default_currency',
    required: true,
    includeIfNull: false,
  )


  final String defaultCurrency;



  @JsonKey(
    
    name: r'default_locale',
    required: true,
    includeIfNull: false,
  )


  final String defaultLocale;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CreateProductRequest &&
      other.sellerId == sellerId &&
      other.categoryId == categoryId &&
      other.brand == brand &&
      other.defaultCurrency == defaultCurrency &&
      other.defaultLocale == defaultLocale;

    @override
    int get hashCode =>
        sellerId.hashCode +
        categoryId.hashCode +
        brand.hashCode +
        defaultCurrency.hashCode +
        defaultLocale.hashCode;

  factory CreateProductRequest.fromJson(Map<String, dynamic> json) => _$CreateProductRequestFromJson(json);

  Map<String, dynamic> toJson() => _$CreateProductRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

