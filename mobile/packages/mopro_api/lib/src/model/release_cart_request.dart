//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'release_cart_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ReleaseCartRequest {
  /// Returns a new [ReleaseCartRequest] instance.
  ReleaseCartRequest({

    required  this.reservationId,
  });

  @JsonKey(
    
    name: r'reservation_id',
    required: true,
    includeIfNull: false,
  )


  final String reservationId;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ReleaseCartRequest &&
      other.reservationId == reservationId;

    @override
    int get hashCode =>
        reservationId.hashCode;

  factory ReleaseCartRequest.fromJson(Map<String, dynamic> json) => _$ReleaseCartRequestFromJson(json);

  Map<String, dynamic> toJson() => _$ReleaseCartRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

