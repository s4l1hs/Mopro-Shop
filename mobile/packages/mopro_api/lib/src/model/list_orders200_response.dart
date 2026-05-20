//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/pagination_meta.dart';
import 'package:mopro_api/src/model/order.dart';
import 'package:json_annotation/json_annotation.dart';

part 'list_orders200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ListOrders200Response {
  /// Returns a new [ListOrders200Response] instance.
  ListOrders200Response({

    required  this.data,

    required  this.pagination,
  });

  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final List<Order> data;



  @JsonKey(
    
    name: r'pagination',
    required: true,
    includeIfNull: false,
  )


  final PaginationMeta pagination;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ListOrders200Response &&
      other.data == data &&
      other.pagination == pagination;

    @override
    int get hashCode =>
        data.hashCode +
        pagination.hashCode;

  factory ListOrders200Response.fromJson(Map<String, dynamic> json) => _$ListOrders200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ListOrders200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

