//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'cashback_preview.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CashbackPreview {
  /// Returns a new [CashbackPreview] instance.
  CashbackPreview({

    required  this.monthlyCoinMinor,

    required  this.currency,
  });

  @JsonKey(
    
    name: r'monthly_coin_minor',
    required: true,
    includeIfNull: false,
  )


  final int monthlyCoinMinor;



  @JsonKey(
    
    name: r'currency',
    required: true,
    includeIfNull: false,
  )


  final String currency;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CashbackPreview &&
      other.monthlyCoinMinor == monthlyCoinMinor &&
      other.currency == currency;

    @override
    int get hashCode =>
        monthlyCoinMinor.hashCode +
        currency.hashCode;

  factory CashbackPreview.fromJson(Map<String, dynamic> json) => _$CashbackPreviewFromJson(json);

  Map<String, dynamic> toJson() => _$CashbackPreviewToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

