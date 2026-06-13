//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'return_request_items_inner.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ReturnRequestItemsInner {
  /// Returns a new [ReturnRequestItemsInner] instance.
  ReturnRequestItemsInner({

    required  this.orderItemId,

    required  this.quantity,

     this.reason,

     this.note,
  });

  @JsonKey(
    
    name: r'order_item_id',
    required: true,
    includeIfNull: false,
  )


  final int orderItemId;



          // minimum: 1
  @JsonKey(
    
    name: r'quantity',
    required: true,
    includeIfNull: false,
  )


  final int quantity;



      /// RT-05: optional per-line return reason. When omitted the header reason applies. 
  @JsonKey(
    
    name: r'reason',
    required: false,
    includeIfNull: false,
  )


  final ReturnRequestItemsInnerReasonEnum? reason;



      /// RT-05: optional per-line free-text note. 
  @JsonKey(
    
    name: r'note',
    required: false,
    includeIfNull: false,
  )


  final String? note;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ReturnRequestItemsInner &&
      other.orderItemId == orderItemId &&
      other.quantity == quantity &&
      other.reason == reason &&
      other.note == note;

    @override
    int get hashCode =>
        orderItemId.hashCode +
        quantity.hashCode +
        reason.hashCode +
        note.hashCode;

  factory ReturnRequestItemsInner.fromJson(Map<String, dynamic> json) => _$ReturnRequestItemsInnerFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnRequestItemsInnerToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

/// RT-05: optional per-line return reason. When omitted the header reason applies. 
enum ReturnRequestItemsInnerReasonEnum {
    /// RT-05: optional per-line return reason. When omitted the header reason applies. 
@JsonValue(r'wrong_product')
wrongProduct(r'wrong_product'),
    /// RT-05: optional per-line return reason. When omitted the header reason applies. 
@JsonValue(r'not_as_described')
notAsDescribed(r'not_as_described'),
    /// RT-05: optional per-line return reason. When omitted the header reason applies. 
@JsonValue(r'damaged')
damaged(r'damaged'),
    /// RT-05: optional per-line return reason. When omitted the header reason applies. 
@JsonValue(r'size_issue')
sizeIssue(r'size_issue'),
    /// RT-05: optional per-line return reason. When omitted the header reason applies. 
@JsonValue(r'changed_mind')
changedMind(r'changed_mind'),
    /// RT-05: optional per-line return reason. When omitted the header reason applies. 
@JsonValue(r'other')
other(r'other');

const ReturnRequestItemsInnerReasonEnum(this.value);

final String value;

@override
String toString() => value;
}


