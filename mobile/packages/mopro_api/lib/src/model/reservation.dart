//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'reservation.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Reservation {
  /// Returns a new [Reservation] instance.
  Reservation({

    required  this.id,

    required  this.expiresAt,
  });

      /// Reservation ID; pass to POST /orders or POST /orders/checkout
  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final String id;



      /// Reservation is released automatically after this time (typically 10 min)
  @JsonKey(
    
    name: r'expires_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime expiresAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Reservation &&
      other.id == id &&
      other.expiresAt == expiresAt;

    @override
    int get hashCode =>
        id.hashCode +
        expiresAt.hashCode;

  factory Reservation.fromJson(Map<String, dynamic> json) => _$ReservationFromJson(json);

  Map<String, dynamic> toJson() => _$ReservationToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

