//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/cashback_plan.dart';
import 'package:mopro_api/src/model/cursor_pagination_meta.dart';
import 'package:json_annotation/json_annotation.dart';

part 'list_cashback_plans200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ListCashbackPlans200Response {
  /// Returns a new [ListCashbackPlans200Response] instance.
  ListCashbackPlans200Response({

    required  this.data,

    required  this.pagination,
  });

  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final List<CashbackPlan> data;



  @JsonKey(
    
    name: r'pagination',
    required: true,
    includeIfNull: false,
  )


  final CursorPaginationMeta pagination;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ListCashbackPlans200Response &&
      other.data == data &&
      other.pagination == pagination;

    @override
    int get hashCode =>
        data.hashCode +
        pagination.hashCode;

  factory ListCashbackPlans200Response.fromJson(Map<String, dynamic> json) => _$ListCashbackPlans200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ListCashbackPlans200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

