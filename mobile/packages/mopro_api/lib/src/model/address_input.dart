//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'address_input.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AddressInput {
  /// Returns a new [AddressInput] instance.
  AddressInput({

    required  this.label,

    required  this.name,

    required  this.phone,

    required  this.city,

    required  this.district,

     this.neighborhood,

    required  this.fullAddress,

     this.postalCode,

     this.isDefault = false,
  });

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
    defaultValue: false,
    name: r'is_default',
    required: false,
    includeIfNull: false,
  )


  final bool? isDefault;





    @override
    bool operator ==(Object other) => identical(this, other) || other is AddressInput &&
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
        label.hashCode +
        name.hashCode +
        phone.hashCode +
        city.hashCode +
        district.hashCode +
        neighborhood.hashCode +
        fullAddress.hashCode +
        postalCode.hashCode +
        isDefault.hashCode;

  factory AddressInput.fromJson(Map<String, dynamic> json) => _$AddressInputFromJson(json);

  Map<String, dynamic> toJson() => _$AddressInputToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

