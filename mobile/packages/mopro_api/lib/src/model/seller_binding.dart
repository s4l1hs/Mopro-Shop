//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'seller_binding.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SellerBinding {
  /// Returns a new [SellerBinding] instance.
  SellerBinding({

    required  this.sellerId,

    required  this.sellerSlug,

    required  this.sellerName,

    required  this.role,
  });

  @JsonKey(
    
    name: r'seller_id',
    required: true,
    includeIfNull: false,
  )


  final int sellerId;



  @JsonKey(
    
    name: r'seller_slug',
    required: true,
    includeIfNull: false,
  )


  final String sellerSlug;



  @JsonKey(
    
    name: r'seller_name',
    required: true,
    includeIfNull: false,
  )


  final String sellerName;



  @JsonKey(
    
    name: r'role',
    required: true,
    includeIfNull: false,
  )


  final SellerBindingRoleEnum role;





    @override
    bool operator ==(Object other) => identical(this, other) || other is SellerBinding &&
      other.sellerId == sellerId &&
      other.sellerSlug == sellerSlug &&
      other.sellerName == sellerName &&
      other.role == role;

    @override
    int get hashCode =>
        sellerId.hashCode +
        sellerSlug.hashCode +
        sellerName.hashCode +
        role.hashCode;

  factory SellerBinding.fromJson(Map<String, dynamic> json) => _$SellerBindingFromJson(json);

  Map<String, dynamic> toJson() => _$SellerBindingToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum SellerBindingRoleEnum {
@JsonValue(r'owner')
owner(r'owner'),
@JsonValue(r'staff')
staff(r'staff');

const SellerBindingRoleEnum(this.value);

final String value;

@override
String toString() => value;
}


