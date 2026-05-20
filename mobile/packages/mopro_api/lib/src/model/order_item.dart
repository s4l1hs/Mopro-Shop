//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'order_item.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class OrderItem {
  /// Returns a new [OrderItem] instance.
  OrderItem({

    required  this.id,

    required  this.variantId,

    required  this.productId,

    required  this.title,

    required  this.quantity,

    required  this.priceMinor,

    required  this.priceCurrency,

    required  this.commissionPctBps,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



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



          // minimum: 1
  @JsonKey(
    
    name: r'quantity',
    required: true,
    includeIfNull: false,
  )


  final int quantity;



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



      /// Snapshotted at sale time from ref_schema.commission_rules. Never changes after order creation.
  @JsonKey(
    
    name: r'commission_pct_bps',
    required: true,
    includeIfNull: false,
  )


  final int commissionPctBps;





    @override
    bool operator ==(Object other) => identical(this, other) || other is OrderItem &&
      other.id == id &&
      other.variantId == variantId &&
      other.productId == productId &&
      other.title == title &&
      other.quantity == quantity &&
      other.priceMinor == priceMinor &&
      other.priceCurrency == priceCurrency &&
      other.commissionPctBps == commissionPctBps;

    @override
    int get hashCode =>
        id.hashCode +
        variantId.hashCode +
        productId.hashCode +
        title.hashCode +
        quantity.hashCode +
        priceMinor.hashCode +
        priceCurrency.hashCode +
        commissionPctBps.hashCode;

  factory OrderItem.fromJson(Map<String, dynamic> json) => _$OrderItemFromJson(json);

  Map<String, dynamic> toJson() => _$OrderItemToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

