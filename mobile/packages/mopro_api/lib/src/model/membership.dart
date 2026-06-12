//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'membership.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Membership {
  /// Returns a new [Membership] instance.
  Membership({

    required  this.tier,

    required  this.rank,

    required  this.windowDays,

    required  this.spendMinor,

    required  this.orderCount,

    required  this.currency,

     this.nextTier,

     this.nextMinSpendMinor,

     this.nextMinOrders,
  });

      /// Current tier code (e.g. classic, gold, elite).
  @JsonKey(
    
    name: r'tier',
    required: true,
    includeIfNull: false,
  )


  final String tier;



      /// 1-based ladder position of the current tier.
  @JsonKey(
    
    name: r'rank',
    required: true,
    includeIfNull: false,
  )


  final int rank;



      /// Rolling qualification window length in days.
  @JsonKey(
    
    name: r'window_days',
    required: true,
    includeIfNull: false,
  )


  final int windowDays;



      /// Delivered-order spend in the window, minor units.
  @JsonKey(
    
    name: r'spend_minor',
    required: true,
    includeIfNull: false,
  )


  final int spendMinor;



      /// Delivered orders in the window.
  @JsonKey(
    
    name: r'order_count',
    required: true,
    includeIfNull: false,
  )


  final int orderCount;



      /// Currency of spend_minor and the thresholds.
  @JsonKey(
    
    name: r'currency',
    required: true,
    includeIfNull: false,
  )


  final String currency;



      /// Next tier code; omitted at the top tier.
  @JsonKey(
    
    name: r'next_tier',
    required: false,
    includeIfNull: false,
  )


  final String? nextTier;



      /// Spend threshold of the next tier, minor units.
  @JsonKey(
    
    name: r'next_min_spend_minor',
    required: false,
    includeIfNull: false,
  )


  final int? nextMinSpendMinor;



      /// Order-count threshold of the next tier.
  @JsonKey(
    
    name: r'next_min_orders',
    required: false,
    includeIfNull: false,
  )


  final int? nextMinOrders;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Membership &&
      other.tier == tier &&
      other.rank == rank &&
      other.windowDays == windowDays &&
      other.spendMinor == spendMinor &&
      other.orderCount == orderCount &&
      other.currency == currency &&
      other.nextTier == nextTier &&
      other.nextMinSpendMinor == nextMinSpendMinor &&
      other.nextMinOrders == nextMinOrders;

    @override
    int get hashCode =>
        tier.hashCode +
        rank.hashCode +
        windowDays.hashCode +
        spendMinor.hashCode +
        orderCount.hashCode +
        currency.hashCode +
        nextTier.hashCode +
        nextMinSpendMinor.hashCode +
        nextMinOrders.hashCode;

  factory Membership.fromJson(Map<String, dynamic> json) => _$MembershipFromJson(json);

  Map<String, dynamic> toJson() => _$MembershipToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

