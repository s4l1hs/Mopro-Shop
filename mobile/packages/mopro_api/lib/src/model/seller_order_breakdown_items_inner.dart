//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'seller_order_breakdown_items_inner.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SellerOrderBreakdownItemsInner {
  /// Returns a new [SellerOrderBreakdownItemsInner] instance.
  SellerOrderBreakdownItemsInner({

    required  this.productTitle,

    required  this.quantity,

    required  this.grossMinor,

    required  this.commissionMinor,

     this.commissionPct,

    required  this.kdvMinor,

    required  this.serviceFeeMinor,

    required  this.netMinor,

    required  this.currency,
  });

  @JsonKey(
    
    name: r'product_title',
    required: true,
    includeIfNull: false,
  )


  final String productTitle;



  @JsonKey(
    
    name: r'quantity',
    required: true,
    includeIfNull: false,
  )


  final int quantity;



  @JsonKey(
    
    name: r'gross_minor',
    required: true,
    includeIfNull: false,
  )


  final int grossMinor;



  @JsonKey(
    
    name: r'commission_minor',
    required: true,
    includeIfNull: false,
  )


  final int commissionMinor;



  @JsonKey(
    
    name: r'commission_pct',
    required: false,
    includeIfNull: false,
  )


  final double? commissionPct;



  @JsonKey(
    
    name: r'kdv_minor',
    required: true,
    includeIfNull: false,
  )


  final int kdvMinor;



      /// Always 0 for Mopro. Non-zero in competitor comparison.
  @JsonKey(
    
    name: r'service_fee_minor',
    required: true,
    includeIfNull: false,
  )


  final int serviceFeeMinor;



  @JsonKey(
    
    name: r'net_minor',
    required: true,
    includeIfNull: false,
  )


  final int netMinor;



  @JsonKey(
    
    name: r'currency',
    required: true,
    includeIfNull: false,
  )


  final String currency;





    @override
    bool operator ==(Object other) => identical(this, other) || other is SellerOrderBreakdownItemsInner &&
      other.productTitle == productTitle &&
      other.quantity == quantity &&
      other.grossMinor == grossMinor &&
      other.commissionMinor == commissionMinor &&
      other.commissionPct == commissionPct &&
      other.kdvMinor == kdvMinor &&
      other.serviceFeeMinor == serviceFeeMinor &&
      other.netMinor == netMinor &&
      other.currency == currency;

    @override
    int get hashCode =>
        productTitle.hashCode +
        quantity.hashCode +
        grossMinor.hashCode +
        commissionMinor.hashCode +
        commissionPct.hashCode +
        kdvMinor.hashCode +
        serviceFeeMinor.hashCode +
        netMinor.hashCode +
        currency.hashCode;

  factory SellerOrderBreakdownItemsInner.fromJson(Map<String, dynamic> json) => _$SellerOrderBreakdownItemsInnerFromJson(json);

  Map<String, dynamic> toJson() => _$SellerOrderBreakdownItemsInnerToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

