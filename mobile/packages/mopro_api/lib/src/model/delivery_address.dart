//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'delivery_address.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DeliveryAddress {
  /// Returns a new [DeliveryAddress] instance.
  DeliveryAddress({

     this.label,

    required  this.recipientName,

     this.phone,

    required  this.fullAddress,

     this.neighborhood,

    required  this.district,

    required  this.city,

     this.postalCode,
  });

      /// User's label for the address (e.g. \"Ev\", \"İş\").
  @JsonKey(
    
    name: r'label',
    required: false,
    includeIfNull: false,
  )


  final String? label;



  @JsonKey(
    
    name: r'recipient_name',
    required: true,
    includeIfNull: false,
  )


  final String recipientName;



  @JsonKey(
    
    name: r'phone',
    required: false,
    includeIfNull: false,
  )


  final String? phone;



  @JsonKey(
    
    name: r'full_address',
    required: true,
    includeIfNull: false,
  )


  final String fullAddress;



  @JsonKey(
    
    name: r'neighborhood',
    required: false,
    includeIfNull: false,
  )


  final String? neighborhood;



  @JsonKey(
    
    name: r'district',
    required: true,
    includeIfNull: false,
  )


  final String district;



  @JsonKey(
    
    name: r'city',
    required: true,
    includeIfNull: false,
  )


  final String city;



  @JsonKey(
    
    name: r'postal_code',
    required: false,
    includeIfNull: false,
  )


  final String? postalCode;





    @override
    bool operator ==(Object other) => identical(this, other) || other is DeliveryAddress &&
      other.label == label &&
      other.recipientName == recipientName &&
      other.phone == phone &&
      other.fullAddress == fullAddress &&
      other.neighborhood == neighborhood &&
      other.district == district &&
      other.city == city &&
      other.postalCode == postalCode;

    @override
    int get hashCode =>
        label.hashCode +
        recipientName.hashCode +
        phone.hashCode +
        fullAddress.hashCode +
        neighborhood.hashCode +
        district.hashCode +
        city.hashCode +
        postalCode.hashCode;

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) => _$DeliveryAddressFromJson(json);

  Map<String, dynamic> toJson() => _$DeliveryAddressToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

