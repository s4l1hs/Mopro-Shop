//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'checkout_response_payment.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CheckoutResponsePayment {
  /// Returns a new [CheckoutResponsePayment] instance.
  CheckoutResponsePayment({

    required  this.requires3ds,

     this.redirectUrl,
  });

  @JsonKey(
    
    name: r'requires_3ds',
    required: true,
    includeIfNull: false,
  )


  final bool requires3ds;



      /// PSP 3DS redirect URL. Null when requires_3ds=false.
  @JsonKey(
    
    name: r'redirect_url',
    required: false,
    includeIfNull: false,
  )


  final String? redirectUrl;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CheckoutResponsePayment &&
      other.requires3ds == requires3ds &&
      other.redirectUrl == redirectUrl;

    @override
    int get hashCode =>
        requires3ds.hashCode +
        redirectUrl.hashCode;

  factory CheckoutResponsePayment.fromJson(Map<String, dynamic> json) => _$CheckoutResponsePaymentFromJson(json);

  Map<String, dynamic> toJson() => _$CheckoutResponsePaymentToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

