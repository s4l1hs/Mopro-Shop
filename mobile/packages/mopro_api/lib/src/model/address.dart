//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'address.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Address {
  /// Returns a new [Address] instance.
  Address({

    required  this.id,

    required  this.label,

    required  this.name,

    required  this.phone,

    required  this.city,

    required  this.district,

     this.neighborhood,

    required  this.fullAddress,

     this.postalCode,

    required  this.isDefault,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'label',
    required: true,
    includeIfNull: false,
  )


  final String label;



  @JsonKey(
    
    name: r'name',
    required: true,
    includeIfNull: false,
  )


  final String name;



  @JsonKey(
    
    name: r'phone',
    required: true,
    includeIfNull: false,
  )


  final String phone;



  @JsonKey(
    
    name: r'city',
    required: true,
    includeIfNull: false,
  )


  final String city;



  @JsonKey(
    
    name: r'district',
    required: true,
    includeIfNull: false,
  )


  final String district;



  @JsonKey(
    
    name: r'neighborhood',
    required: false,
    includeIfNull: false,
  )


  final String? neighborhood;



  @JsonKey(
    
    name: r'full_address',
    required: true,
    includeIfNull: false,
  )


  final String fullAddress;



  @JsonKey(
    
    name: r'postal_code',
    required: false,
    includeIfNull: false,
  )


  final String? postalCode;



  @JsonKey(
    
    name: r'is_default',
    required: true,
    includeIfNull: false,
  )


  final bool isDefault;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Address &&
      other.id == id &&
      other.label == label &&
      other.name == name &&
      other.phone == phone &&
      other.city == city &&
      other.district == district &&
      other.neighborhood == neighborhood &&
      other.fullAddress == fullAddress &&
      other.postalCode == postalCode &&
      other.isDefault == isDefault;

    @override
    int get hashCode =>
        id.hashCode +
        label.hashCode +
        name.hashCode +
        phone.hashCode +
        city.hashCode +
        district.hashCode +
        neighborhood.hashCode +
        fullAddress.hashCode +
        postalCode.hashCode +
        isDefault.hashCode;

  factory Address.fromJson(Map<String, dynamic> json) => _$AddressFromJson(json);

  Map<String, dynamic> toJson() => _$AddressToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

