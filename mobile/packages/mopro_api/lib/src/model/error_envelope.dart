//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/error_envelope_error.dart';
import 'package:json_annotation/json_annotation.dart';

part 'error_envelope.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ErrorEnvelope {
  /// Returns a new [ErrorEnvelope] instance.
  ErrorEnvelope({

    required  this.error,
  });

  @JsonKey(
    
    name: r'error',
    required: true,
    includeIfNull: false,
  )


  final ErrorEnvelopeError error;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ErrorEnvelope &&
      other.error == error;

    @override
    int get hashCode =>
        error.hashCode;

  factory ErrorEnvelope.fromJson(Map<String, dynamic> json) => _$ErrorEnvelopeFromJson(json);

  Map<String, dynamic> toJson() => _$ErrorEnvelopeToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

