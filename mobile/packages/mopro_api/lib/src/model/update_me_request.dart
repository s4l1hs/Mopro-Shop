//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'update_me_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class UpdateMeRequest {
  /// Returns a new [UpdateMeRequest] instance.
  UpdateMeRequest({

     this.nameFirst,

     this.nameLast,

     this.email,

     this.locale,
  });

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
    required: false,
    includeIfNull: false,
  )


  final String? locale;





    @override
    bool operator ==(Object other) => identical(this, other) || other is UpdateMeRequest &&
      other.nameFirst == nameFirst &&
      other.nameLast == nameLast &&
      other.email == email &&
      other.locale == locale;

    @override
    int get hashCode =>
        nameFirst.hashCode +
        nameLast.hashCode +
        email.hashCode +
        locale.hashCode;

  factory UpdateMeRequest.fromJson(Map<String, dynamic> json) => _$UpdateMeRequestFromJson(json);

  Map<String, dynamic> toJson() => _$UpdateMeRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

