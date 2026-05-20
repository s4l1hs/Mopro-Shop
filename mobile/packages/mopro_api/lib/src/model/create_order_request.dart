//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'create_order_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CreateOrderRequest {
  /// Returns a new [CreateOrderRequest] instance.
  CreateOrderRequest({

    required  this.reservationId,

    required  this.addressId,
  });

  @JsonKey(
    
    name: r'reservation_id',
    required: true,
    includeIfNull: false,
  )


  final String reservationId;



  @JsonKey(
    
    name: r'address_id',
    required: true,
    includeIfNull: false,
  )


  final int addressId;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CreateOrderRequest &&
      other.reservationId == reservationId &&
      other.addressId == addressId;

    @override
    int get hashCode =>
        reservationId.hashCode +
        addressId.hashCode;

  factory CreateOrderRequest.fromJson(Map<String, dynamic> json) => _$CreateOrderRequestFromJson(json);

  Map<String, dynamic> toJson() => _$CreateOrderRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

