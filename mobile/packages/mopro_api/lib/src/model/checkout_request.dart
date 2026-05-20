//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/checkout_request_payment_method.dart';
import 'package:json_annotation/json_annotation.dart';

part 'checkout_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CheckoutRequest {
  /// Returns a new [CheckoutRequest] instance.
  CheckoutRequest({

    required  this.addressId,

    required  this.cargoOption,

    required  this.paymentMethod,
  });

  @JsonKey(
    
    name: r'address_id',
    required: true,
    includeIfNull: false,
  )


  final int addressId;



  @JsonKey(
    
    name: r'cargo_option',
    required: true,
    includeIfNull: false,
  )


  final CheckoutRequestCargoOptionEnum cargoOption;



  @JsonKey(
    
    name: r'payment_method',
    required: true,
    includeIfNull: false,
  )


  final CheckoutRequestPaymentMethod paymentMethod;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CheckoutRequest &&
      other.addressId == addressId &&
      other.cargoOption == cargoOption &&
      other.paymentMethod == paymentMethod;

    @override
    int get hashCode =>
        addressId.hashCode +
        cargoOption.hashCode +
        paymentMethod.hashCode;

  factory CheckoutRequest.fromJson(Map<String, dynamic> json) => _$CheckoutRequestFromJson(json);

  Map<String, dynamic> toJson() => _$CheckoutRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum CheckoutRequestCargoOptionEnum {
@JsonValue(r'aras')
aras(r'aras'),
@JsonValue(r'yurtici')
yurtici(r'yurtici'),
@JsonValue(r'surat')
surat(r'surat'),
@JsonValue(r'mng')
mng(r'mng'),
@JsonValue(r'hepsijet')
hepsijet(r'hepsijet'),
@JsonValue(r'ptt')
ptt(r'ptt');

const CheckoutRequestCargoOptionEnum(this.value);

final String value;

@override
String toString() => value;
}


