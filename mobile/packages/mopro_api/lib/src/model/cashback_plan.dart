//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'cashback_plan.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CashbackPlan {
  /// Returns a new [CashbackPlan] instance.
  CashbackPlan({

    required  this.id,

    required  this.orderId,

    required  this.productId,

    required  this.productTitle,

     this.productImageUrl,

    required  this.monthlyAmountMinor,

    required  this.currency,

    required  this.status,

    required  this.startDate,

    required  this.referenceInterestRateBps,

    required  this.createdAt,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'order_id',
    required: true,
    includeIfNull: false,
  )


  final int orderId;



  @JsonKey(
    
    name: r'product_id',
    required: true,
    includeIfNull: false,
  )


  final int productId;



  @JsonKey(
    
    name: r'product_title',
    required: true,
    includeIfNull: false,
  )


  final String productTitle;



  @JsonKey(
    
    name: r'product_image_url',
    required: false,
    includeIfNull: false,
  )


  final String? productImageUrl;



  @JsonKey(
    
    name: r'monthly_amount_minor',
    required: true,
    includeIfNull: false,
  )


  final int monthlyAmountMinor;



  @JsonKey(
    
    name: r'currency',
    required: true,
    includeIfNull: false,
  )


  final String currency;



  @JsonKey(
    
    name: r'status',
    required: true,
    includeIfNull: false,
  )


  final CashbackPlanStatusEnum status;



      /// ISO 8601 date (YYYY-MM-DD). First instalment paid on or after this date.
  @JsonKey(
    
    name: r'start_date',
    required: true,
    includeIfNull: false,
  )


  final DateTime startDate;



      /// Reference rate in basis points (5000 = 50%). Frozen at plan creation time per the v6 perpetual cashback formula. Existing plans retain their original rate even if the platform's reference rate changes later. See LEDGER_GUIDE.md §3.4 for the formula derivation. 
  @JsonKey(
    
    name: r'reference_interest_rate_bps',
    required: true,
    includeIfNull: false,
  )


  final int referenceInterestRateBps;



  @JsonKey(
    
    name: r'created_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime createdAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CashbackPlan &&
      other.id == id &&
      other.orderId == orderId &&
      other.productId == productId &&
      other.productTitle == productTitle &&
      other.productImageUrl == productImageUrl &&
      other.monthlyAmountMinor == monthlyAmountMinor &&
      other.currency == currency &&
      other.status == status &&
      other.startDate == startDate &&
      other.referenceInterestRateBps == referenceInterestRateBps &&
      other.createdAt == createdAt;

    @override
    int get hashCode =>
        id.hashCode +
        orderId.hashCode +
        productId.hashCode +
        productTitle.hashCode +
        productImageUrl.hashCode +
        monthlyAmountMinor.hashCode +
        currency.hashCode +
        status.hashCode +
        startDate.hashCode +
        referenceInterestRateBps.hashCode +
        createdAt.hashCode;

  factory CashbackPlan.fromJson(Map<String, dynamic> json) => _$CashbackPlanFromJson(json);

  Map<String, dynamic> toJson() => _$CashbackPlanToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum CashbackPlanStatusEnum {
@JsonValue(r'active')
active(r'active'),
@JsonValue(r'cancelled')
cancelled(r'cancelled'),
@JsonValue(r'suspended')
suspended(r'suspended');

const CashbackPlanStatusEnum(this.value);

final String value;

@override
String toString() => value;
}


