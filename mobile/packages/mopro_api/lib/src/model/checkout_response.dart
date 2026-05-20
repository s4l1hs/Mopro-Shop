//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/checkout_response_payment.dart';
import 'package:json_annotation/json_annotation.dart';

part 'checkout_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CheckoutResponse {
  /// Returns a new [CheckoutResponse] instance.
  CheckoutResponse({

    required  this.orderId,

    required  this.status,

    required  this.totalMinor,

    required  this.currency,

    required  this.payment,
  });

  @JsonKey(
    
    name: r'order_id',
    required: true,
    includeIfNull: false,
  )


  final int orderId;



  @JsonKey(
    
    name: r'status',
    required: true,
    includeIfNull: false,
  )


  final CheckoutResponseStatusEnum status;



  @JsonKey(
    
    name: r'total_minor',
    required: true,
    includeIfNull: false,
  )


  final int totalMinor;



  @JsonKey(
    
    name: r'currency',
    required: true,
    includeIfNull: false,
  )


  final String currency;



  @JsonKey(
    
    name: r'payment',
    required: true,
    includeIfNull: false,
  )


  final CheckoutResponsePayment payment;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CheckoutResponse &&
      other.orderId == orderId &&
      other.status == status &&
      other.totalMinor == totalMinor &&
      other.currency == currency &&
      other.payment == payment;

    @override
    int get hashCode =>
        orderId.hashCode +
        status.hashCode +
        totalMinor.hashCode +
        currency.hashCode +
        payment.hashCode;

  factory CheckoutResponse.fromJson(Map<String, dynamic> json) => _$CheckoutResponseFromJson(json);

  Map<String, dynamic> toJson() => _$CheckoutResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum CheckoutResponseStatusEnum {
@JsonValue(r'awaiting_payment')
awaitingPayment(r'awaiting_payment'),
@JsonValue(r'confirmed')
confirmed(r'confirmed');

const CheckoutResponseStatusEnum(this.value);

final String value;

@override
String toString() => value;
}


