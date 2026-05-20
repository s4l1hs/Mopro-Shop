//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'variant.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Variant {
  /// Returns a new [Variant] instance.
  Variant({

    required  this.id,

    required  this.sku,

     this.color,

     this.size,

    required  this.priceMinor,

    required  this.priceCurrency,

    required  this.stock,

    required  this.imageUrls,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'sku',
    required: true,
    includeIfNull: false,
  )


  final String sku;



  @JsonKey(
    
    name: r'color',
    required: false,
    includeIfNull: false,
  )


  final String? color;



  @JsonKey(
    
    name: r'size',
    required: false,
    includeIfNull: false,
  )


  final String? size;



      /// Price in minor units (kuruş)
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



          // minimum: 0
  @JsonKey(
    
    name: r'stock',
    required: true,
    includeIfNull: false,
  )


  final int stock;



      /// CDN-resolved full URLs. Never raw storage keys.
  @JsonKey(
    
    name: r'image_urls',
    required: true,
    includeIfNull: false,
  )


  final List<String> imageUrls;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Variant &&
      other.id == id &&
      other.sku == sku &&
      other.color == color &&
      other.size == size &&
      other.priceMinor == priceMinor &&
      other.priceCurrency == priceCurrency &&
      other.stock == stock &&
      other.imageUrls == imageUrls;

    @override
    int get hashCode =>
        id.hashCode +
        sku.hashCode +
        color.hashCode +
        size.hashCode +
        priceMinor.hashCode +
        priceCurrency.hashCode +
        stock.hashCode +
        imageUrls.hashCode;

  factory Variant.fromJson(Map<String, dynamic> json) => _$VariantFromJson(json);

  Map<String, dynamic> toJson() => _$VariantToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

