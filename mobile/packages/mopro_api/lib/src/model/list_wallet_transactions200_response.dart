//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/wallet_transaction.dart';
import 'package:mopro_api/src/model/cursor_pagination_meta.dart';
import 'package:json_annotation/json_annotation.dart';

part 'list_wallet_transactions200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ListWalletTransactions200Response {
  /// Returns a new [ListWalletTransactions200Response] instance.
  ListWalletTransactions200Response({

    required  this.data,

    required  this.pagination,
  });

  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final List<WalletTransaction> data;



  @JsonKey(
    
    name: r'pagination',
    required: true,
    includeIfNull: false,
  )


  final CursorPaginationMeta pagination;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ListWalletTransactions200Response &&
      other.data == data &&
      other.pagination == pagination;

    @override
    int get hashCode =>
        data.hashCode +
        pagination.hashCode;

  factory ListWalletTransactions200Response.fromJson(Map<String, dynamic> json) => _$ListWalletTransactions200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ListWalletTransactions200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

