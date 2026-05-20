//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'delete_me_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DeleteMeRequest {
  /// Returns a new [DeleteMeRequest] instance.
  DeleteMeRequest({

    required  this.reason,
  });

  @JsonKey(
    
    name: r'reason',
    required: true,
    includeIfNull: false,
  )


  final DeleteMeRequestReasonEnum reason;





    @override
    bool operator ==(Object other) => identical(this, other) || other is DeleteMeRequest &&
      other.reason == reason;

    @override
    int get hashCode =>
        reason.hashCode;

  factory DeleteMeRequest.fromJson(Map<String, dynamic> json) => _$DeleteMeRequestFromJson(json);

  Map<String, dynamic> toJson() => _$DeleteMeRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum DeleteMeRequestReasonEnum {
@JsonValue(r'no_longer_needed')
noLongerNeeded(r'no_longer_needed'),
@JsonValue(r'privacy_concern')
privacyConcern(r'privacy_concern'),
@JsonValue(r'bad_experience')
badExperience(r'bad_experience'),
@JsonValue(r'switching_platform')
switchingPlatform(r'switching_platform'),
@JsonValue(r'other')
other(r'other');

const DeleteMeRequestReasonEnum(this.value);

final String value;

@override
String toString() => value;
}


