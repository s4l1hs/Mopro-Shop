//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'checkout_request_payment_method.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CheckoutRequestPaymentMethod {
  /// Returns a new [CheckoutRequestPaymentMethod] instance.
  CheckoutRequestPaymentMethod({

    required  this.type,

     this.savedCardId,
  });

  @JsonKey(
    
    name: r'type',
    required: true,
    includeIfNull: false,
  )


  final CheckoutRequestPaymentMethodTypeEnum type;



      /// PSP-tokenized card ID. Required when type=card and using a saved card.
  @JsonKey(
    
    name: r'saved_card_id',
    required: false,
    includeIfNull: false,
  )


  final String? savedCardId;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CheckoutRequestPaymentMethod &&
      other.type == type &&
      other.savedCardId == savedCardId;

    @override
    int get hashCode =>
        type.hashCode +
        savedCardId.hashCode;

  factory CheckoutRequestPaymentMethod.fromJson(Map<String, dynamic> json) => _$CheckoutRequestPaymentMethodFromJson(json);

  Map<String, dynamic> toJson() => _$CheckoutRequestPaymentMethodToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum CheckoutRequestPaymentMethodTypeEnum {
@JsonValue(r'card')
card(r'card'),
@JsonValue(r'coin_balance')
coinBalance(r'coin_balance');

const CheckoutRequestPaymentMethodTypeEnum(this.value);

final String value;

@override
String toString() => value;
}


