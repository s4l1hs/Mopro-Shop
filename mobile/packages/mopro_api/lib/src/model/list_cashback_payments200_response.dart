//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/cashback_payment.dart';
import 'package:mopro_api/src/model/cursor_pagination_meta.dart';
import 'package:json_annotation/json_annotation.dart';

part 'list_cashback_payments200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ListCashbackPayments200Response {
  /// Returns a new [ListCashbackPayments200Response] instance.
  ListCashbackPayments200Response({

    required  this.data,

    required  this.pagination,
  });

  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final List<CashbackPayment> data;



  @JsonKey(
    
    name: r'pagination',
    required: true,
    includeIfNull: false,
  )


  final CursorPaginationMeta pagination;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ListCashbackPayments200Response &&
      other.data == data &&
      other.pagination == pagination;

    @override
    int get hashCode =>
        data.hashCode +
        pagination.hashCode;

  factory ListCashbackPayments200Response.fromJson(Map<String, dynamic> json) => _$ListCashbackPayments200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ListCashbackPayments200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

