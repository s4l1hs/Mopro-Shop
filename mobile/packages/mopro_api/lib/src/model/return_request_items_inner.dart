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





    @override
    bool operator ==(Object other) => identical(this, other) || other is ReturnRequestItemsInner &&
      other.orderItemId == orderItemId &&
      other.quantity == quantity;

    @override
    int get hashCode =>
        orderItemId.hashCode +
        quantity.hashCode;

  factory ReturnRequestItemsInner.fromJson(Map<String, dynamic> json) => _$ReturnRequestItemsInnerFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnRequestItemsInnerToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

