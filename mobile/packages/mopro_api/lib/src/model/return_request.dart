//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/return_request_items_inner.dart';
import 'package:json_annotation/json_annotation.dart';

part 'return_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ReturnRequest {
  /// Returns a new [ReturnRequest] instance.
  ReturnRequest({

    required  this.reason,

     this.description,

     this.items,
  });

  @JsonKey(
    
    name: r'reason',
    required: true,
    includeIfNull: false,
  )


  final ReturnRequestReasonEnum reason;



  @JsonKey(
    
    name: r'description',
    required: false,
    includeIfNull: false,
  )


  final String? description;



      /// Specific items and quantities to return. If absent, full order return.
  @JsonKey(
    
    name: r'items',
    required: false,
    includeIfNull: false,
  )


  final List<ReturnRequestItemsInner>? items;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ReturnRequest &&
      other.reason == reason &&
      other.description == description &&
      other.items == items;

    @override
    int get hashCode =>
        reason.hashCode +
        description.hashCode +
        items.hashCode;

  factory ReturnRequest.fromJson(Map<String, dynamic> json) => _$ReturnRequestFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum ReturnRequestReasonEnum {
@JsonValue(r'wrong_product')
wrongProduct(r'wrong_product'),
@JsonValue(r'not_as_described')
notAsDescribed(r'not_as_described'),
@JsonValue(r'damaged')
damaged(r'damaged'),
@JsonValue(r'size_issue')
sizeIssue(r'size_issue'),
@JsonValue(r'changed_mind')
changedMind(r'changed_mind'),
@JsonValue(r'other')
other(r'other');

const ReturnRequestReasonEnum(this.value);

final String value;

@override
String toString() => value;
}


