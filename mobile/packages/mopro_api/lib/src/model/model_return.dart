//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'model_return.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ModelReturn {
  /// Returns a new [ModelReturn] instance.
  ModelReturn({

    required  this.id,

    required  this.orderId,

    required  this.status,

    required  this.reason,

     this.description,

    required  this.createdAt,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'order_id',
    required: true,
    includeIfNull: false,
  )


  final int orderId;



  @JsonKey(
    
    name: r'status',
    required: true,
    includeIfNull: false,
  )


  final ModelReturnStatusEnum status;



  @JsonKey(
    
    name: r'reason',
    required: true,
    includeIfNull: false,
  )


  final String reason;



  @JsonKey(
    
    name: r'description',
    required: false,
    includeIfNull: false,
  )


  final String? description;



  @JsonKey(
    
    name: r'created_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime createdAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ModelReturn &&
      other.id == id &&
      other.orderId == orderId &&
      other.status == status &&
      other.reason == reason &&
      other.description == description &&
      other.createdAt == createdAt;

    @override
    int get hashCode =>
        id.hashCode +
        orderId.hashCode +
        status.hashCode +
        reason.hashCode +
        description.hashCode +
        createdAt.hashCode;

  factory ModelReturn.fromJson(Map<String, dynamic> json) => _$ModelReturnFromJson(json);

  Map<String, dynamic> toJson() => _$ModelReturnToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum ModelReturnStatusEnum {
@JsonValue(r'pending')
pending(r'pending'),
@JsonValue(r'approved')
approved(r'approved'),
@JsonValue(r'rejected')
rejected(r'rejected'),
@JsonValue(r'refunded')
refunded(r'refunded');

const ModelReturnStatusEnum(this.value);

final String value;

@override
String toString() => value;
}


