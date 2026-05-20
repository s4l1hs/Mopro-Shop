//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'seller_order_breakdown_totals.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SellerOrderBreakdownTotals {
  /// Returns a new [SellerOrderBreakdownTotals] instance.
  SellerOrderBreakdownTotals({

    required  this.grossMinor,

    required  this.commissionMinor,

    required  this.kdvMinor,

    required  this.netMinor,

    required  this.currency,
  });

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
    
    name: r'kdv_minor',
    required: true,
    includeIfNull: false,
  )


  final int kdvMinor;



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
    bool operator ==(Object other) => identical(this, other) || other is SellerOrderBreakdownTotals &&
      other.grossMinor == grossMinor &&
      other.commissionMinor == commissionMinor &&
      other.kdvMinor == kdvMinor &&
      other.netMinor == netMinor &&
      other.currency == currency;

    @override
    int get hashCode =>
        grossMinor.hashCode +
        commissionMinor.hashCode +
        kdvMinor.hashCode +
        netMinor.hashCode +
        currency.hashCode;

  factory SellerOrderBreakdownTotals.fromJson(Map<String, dynamic> json) => _$SellerOrderBreakdownTotalsFromJson(json);

  Map<String, dynamic> toJson() => _$SellerOrderBreakdownTotalsToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

