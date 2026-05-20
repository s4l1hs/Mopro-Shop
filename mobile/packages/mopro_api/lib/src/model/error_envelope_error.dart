//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/field_error.dart';
import 'package:json_annotation/json_annotation.dart';

part 'error_envelope_error.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ErrorEnvelopeError {
  /// Returns a new [ErrorEnvelopeError] instance.
  ErrorEnvelopeError({

    required  this.code,

    required  this.message,

    required  this.traceId,

     this.fields,
  });

      /// Machine-readable error slug
  @JsonKey(
    
    name: r'code',
    required: true,
    includeIfNull: false,
  )


  final String code;



      /// Human-readable error message (locale from Accept-Language)
  @JsonKey(
    
    name: r'message',
    required: true,
    includeIfNull: false,
  )


  final String message;



      /// Request trace ID. Echoes X-Trace-Id or server-generated UUID.
  @JsonKey(
    
    name: r'trace_id',
    required: true,
    includeIfNull: false,
  )


  final String traceId;



      /// Per-field validation errors. Present only for 422 responses.
  @JsonKey(
    
    name: r'fields',
    required: false,
    includeIfNull: false,
  )


  final List<FieldError>? fields;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ErrorEnvelopeError &&
      other.code == code &&
      other.message == message &&
      other.traceId == traceId &&
      other.fields == fields;

    @override
    int get hashCode =>
        code.hashCode +
        message.hashCode +
        traceId.hashCode +
        fields.hashCode;

  factory ErrorEnvelopeError.fromJson(Map<String, dynamic> json) => _$ErrorEnvelopeErrorFromJson(json);

  Map<String, dynamic> toJson() => _$ErrorEnvelopeErrorToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

