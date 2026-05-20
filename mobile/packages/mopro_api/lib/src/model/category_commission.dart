//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'category_commission.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CategoryCommission {
  /// Returns a new [CategoryCommission] instance.
  CategoryCommission({

    required  this.categoryId,

    required  this.market,

    required  this.commissionPctBps,

    required  this.kdvPctBps,
  });

  @JsonKey(
    
    name: r'category_id',
    required: true,
    includeIfNull: false,
  )


  final int categoryId;



  @JsonKey(
    
    name: r'market',
    required: true,
    includeIfNull: false,
  )


  final String market;



      /// Commission rate in basis points
  @JsonKey(
    
    name: r'commission_pct_bps',
    required: true,
    includeIfNull: false,
  )


  final int commissionPctBps;



      /// KDV (VAT) rate in basis points
  @JsonKey(
    
    name: r'kdv_pct_bps',
    required: true,
    includeIfNull: false,
  )


  final int kdvPctBps;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CategoryCommission &&
      other.categoryId == categoryId &&
      other.market == market &&
      other.commissionPctBps == commissionPctBps &&
      other.kdvPctBps == kdvPctBps;

    @override
    int get hashCode =>
        categoryId.hashCode +
        market.hashCode +
        commissionPctBps.hashCode +
        kdvPctBps.hashCode;

  factory CategoryCommission.fromJson(Map<String, dynamic> json) => _$CategoryCommissionFromJson(json);

  Map<String, dynamic> toJson() => _$CategoryCommissionToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

