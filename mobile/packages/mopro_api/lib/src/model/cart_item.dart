//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'cart_item.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CartItem {
  /// Returns a new [CartItem] instance.
  CartItem({

    required  this.variantId,

    required  this.productId,

    required  this.title,

     this.imageUrl,

     this.color,

     this.size,

    required  this.priceMinor,

    required  this.priceCurrency,

    required  this.quantity,

    required  this.monthlyCoinMinor,

    required  this.coinCurrency,
  });

  @JsonKey(
    
    name: r'variant_id',
    required: true,
    includeIfNull: false,
  )


  final int variantId;



  @JsonKey(
    
    name: r'product_id',
    required: true,
    includeIfNull: false,
  )


  final int productId;



  @JsonKey(
    
    name: r'title',
    required: true,
    includeIfNull: false,
  )


  final String title;



  @JsonKey(
    
    name: r'image_url',
    required: false,
    includeIfNull: false,
  )


  final String? imageUrl;



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



          // minimum: 1
  @JsonKey(
    
    name: r'quantity',
    required: true,
    includeIfNull: false,
  )


  final int quantity;



      /// Cashback preview per item per month
  @JsonKey(
    
    name: r'monthly_coin_minor',
    required: true,
    includeIfNull: false,
  )


  final int monthlyCoinMinor;



  @JsonKey(
    
    name: r'coin_currency',
    required: true,
    includeIfNull: false,
  )


  final String coinCurrency;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CartItem &&
      other.variantId == variantId &&
      other.productId == productId &&
      other.title == title &&
      other.imageUrl == imageUrl &&
      other.color == color &&
      other.size == size &&
      other.priceMinor == priceMinor &&
      other.priceCurrency == priceCurrency &&
      other.quantity == quantity &&
      other.monthlyCoinMinor == monthlyCoinMinor &&
      other.coinCurrency == coinCurrency;

    @override
    int get hashCode =>
        variantId.hashCode +
        productId.hashCode +
        title.hashCode +
        imageUrl.hashCode +
        color.hashCode +
        size.hashCode +
        priceMinor.hashCode +
        priceCurrency.hashCode +
        quantity.hashCode +
        monthlyCoinMinor.hashCode +
        coinCurrency.hashCode;

  factory CartItem.fromJson(Map<String, dynamic> json) => _$CartItemFromJson(json);

  Map<String, dynamic> toJson() => _$CartItemToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

