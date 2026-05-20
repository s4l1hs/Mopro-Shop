//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'cashback_payment.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CashbackPayment {
  /// Returns a new [CashbackPayment] instance.
  CashbackPayment({

    required  this.id,

    required  this.planId,

    required  this.periodYyyymm,

    required  this.amountMinor,

    required  this.currency,

    required  this.status,

     this.paidAt,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'plan_id',
    required: true,
    includeIfNull: false,
  )


  final int planId;



      /// Year-month of the payment period. e.g. 202601 = January 2026.
  @JsonKey(
    
    name: r'period_yyyymm',
    required: true,
    includeIfNull: false,
  )


  final String periodYyyymm;



  @JsonKey(
    
    name: r'amount_minor',
    required: true,
    includeIfNull: false,
  )


  final int amountMinor;



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


  final CashbackPaymentStatusEnum status;



  @JsonKey(
    
    name: r'paid_at',
    required: false,
    includeIfNull: false,
  )


  final DateTime? paidAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CashbackPayment &&
      other.id == id &&
      other.planId == planId &&
      other.periodYyyymm == periodYyyymm &&
      other.amountMinor == amountMinor &&
      other.currency == currency &&
      other.status == status &&
      other.paidAt == paidAt;

    @override
    int get hashCode =>
        id.hashCode +
        planId.hashCode +
        periodYyyymm.hashCode +
        amountMinor.hashCode +
        currency.hashCode +
        status.hashCode +
        paidAt.hashCode;

  factory CashbackPayment.fromJson(Map<String, dynamic> json) => _$CashbackPaymentFromJson(json);

  Map<String, dynamic> toJson() => _$CashbackPaymentToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum CashbackPaymentStatusEnum {
@JsonValue(r'scheduled')
scheduled(r'scheduled'),
@JsonValue(r'paid')
paid(r'paid'),
@JsonValue(r'failed')
failed(r'failed');

const CashbackPaymentStatusEnum(this.value);

final String value;

@override
String toString() => value;
}


