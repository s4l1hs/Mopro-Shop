//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/seller_order_breakdown_totals.dart';
import 'package:mopro_api/src/model/seller_order_breakdown_items_inner.dart';
import 'package:json_annotation/json_annotation.dart';

part 'seller_order_breakdown.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SellerOrderBreakdown {
  /// Returns a new [SellerOrderBreakdown] instance.
  SellerOrderBreakdown({

    required  this.orderId,

    required  this.items,

    required  this.totals,

    required  this.unlockAt,
  });

  @JsonKey(
    
    name: r'order_id',
    required: true,
    includeIfNull: false,
  )


  final int orderId;



  @JsonKey(
    
    name: r'items',
    required: true,
    includeIfNull: false,
  )


  final List<SellerOrderBreakdownItemsInner> items;



  @JsonKey(
    
    name: r'totals',
    required: true,
    includeIfNull: false,
  )


  final SellerOrderBreakdownTotals totals;



      /// Payout unlock date — delivered_at + 3 business days (TR calendar)
  @JsonKey(
    
    name: r'unlock_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime unlockAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is SellerOrderBreakdown &&
      other.orderId == orderId &&
      other.items == items &&
      other.totals == totals &&
      other.unlockAt == unlockAt;

    @override
    int get hashCode =>
        orderId.hashCode +
        items.hashCode +
        totals.hashCode +
        unlockAt.hashCode;

  factory SellerOrderBreakdown.fromJson(Map<String, dynamic> json) => _$SellerOrderBreakdownFromJson(json);

  Map<String, dynamic> toJson() => _$SellerOrderBreakdownToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

