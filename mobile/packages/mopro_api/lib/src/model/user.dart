//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/seller_binding.dart';
import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class User {
  /// Returns a new [User] instance.
  User({

    required  this.id,

    required  this.phone,

     this.nameFirst,

     this.nameLast,

     this.email,

    required  this.locale,

    required  this.createdAt,

    required  this.updatedAt,

     this.sellerBinding,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'phone',
    required: true,
    includeIfNull: false,
  )


  final String phone;



  @JsonKey(
    
    name: r'name_first',
    required: false,
    includeIfNull: false,
  )


  final String? nameFirst;



  @JsonKey(
    
    name: r'name_last',
    required: false,
    includeIfNull: false,
  )


  final String? nameLast;



  @JsonKey(
    
    name: r'email',
    required: false,
    includeIfNull: false,
  )


  final String? email;



  @JsonKey(
    
    name: r'locale',
    required: true,
    includeIfNull: false,
  )


  final String locale;



  @JsonKey(
    
    name: r'created_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime createdAt;



  @JsonKey(
    
    name: r'updated_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime updatedAt;



      /// The user's seller-account binding, or null when the user is not bound to an active seller. Drives client-side seller-role detection. 
  @JsonKey(
    
    name: r'seller_binding',
    required: false,
    includeIfNull: false,
  )


  final SellerBinding? sellerBinding;





    @override
    bool operator ==(Object other) => identical(this, other) || other is User &&
      other.id == id &&
      other.phone == phone &&
      other.nameFirst == nameFirst &&
      other.nameLast == nameLast &&
      other.email == email &&
      other.locale == locale &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.sellerBinding == sellerBinding;

    @override
    int get hashCode =>
        id.hashCode +
        phone.hashCode +
        nameFirst.hashCode +
        nameLast.hashCode +
        email.hashCode +
        locale.hashCode +
        createdAt.hashCode +
        updatedAt.hashCode +
        sellerBinding.hashCode;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  Map<String, dynamic> toJson() => _$UserToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

