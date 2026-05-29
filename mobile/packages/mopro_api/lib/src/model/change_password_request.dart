//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'change_password_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ChangePasswordRequest {
  /// Returns a new [ChangePasswordRequest] instance.
  ChangePasswordRequest({

    required  this.oldPassword,

    required  this.newPassword,
  });

      /// Current password (plaintext over TLS)
  @JsonKey(
    
    name: r'old_password',
    required: true,
    includeIfNull: false,
  )


  final String oldPassword;



      /// New password (≥8 chars, 1 upper, 1 lower, 1 special)
  @JsonKey(
    
    name: r'new_password',
    required: true,
    includeIfNull: false,
  )


  final String newPassword;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ChangePasswordRequest &&
      other.oldPassword == oldPassword &&
      other.newPassword == newPassword;

    @override
    int get hashCode =>
        oldPassword.hashCode +
        newPassword.hashCode;

  factory ChangePasswordRequest.fromJson(Map<String, dynamic> json) => _$ChangePasswordRequestFromJson(json);

  Map<String, dynamic> toJson() => _$ChangePasswordRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

