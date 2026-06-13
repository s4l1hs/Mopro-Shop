//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/fit_profile.dart';
import 'package:json_annotation/json_annotation.dart';

part 'fit_profile_envelope.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FitProfileEnvelope {
  /// Returns a new [FitProfileEnvelope] instance.
  FitProfileEnvelope({

    required  this.exists,

     this.profile,
  });

  @JsonKey(
    
    name: r'exists',
    required: true,
    includeIfNull: false,
  )


  final bool exists;



  @JsonKey(
    
    name: r'profile',
    required: false,
    includeIfNull: false,
  )


  final FitProfile? profile;





    @override
    bool operator ==(Object other) => identical(this, other) || other is FitProfileEnvelope &&
      other.exists == exists &&
      other.profile == profile;

    @override
    int get hashCode =>
        exists.hashCode +
        profile.hashCode;

  factory FitProfileEnvelope.fromJson(Map<String, dynamic> json) => _$FitProfileEnvelopeFromJson(json);

  Map<String, dynamic> toJson() => _$FitProfileEnvelopeToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

