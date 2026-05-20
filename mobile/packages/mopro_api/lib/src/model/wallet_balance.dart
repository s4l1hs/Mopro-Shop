//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'wallet_balance.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class WalletBalance {
  /// Returns a new [WalletBalance] instance.
  WalletBalance({

    required  this.currency,

    required  this.amountMinor,

    required  this.lastUpdatedAt,
  });

  @JsonKey(
    
    name: r'currency',
    required: true,
    includeIfNull: false,
  )


  final String currency;



  @JsonKey(
    
    name: r'amount_minor',
    required: true,
    includeIfNull: false,
  )


  final int amountMinor;



  @JsonKey(
    
    name: r'last_updated_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime lastUpdatedAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is WalletBalance &&
      other.currency == currency &&
      other.amountMinor == amountMinor &&
      other.lastUpdatedAt == lastUpdatedAt;

    @override
    int get hashCode =>
        currency.hashCode +
        amountMinor.hashCode +
        lastUpdatedAt.hashCode;

  factory WalletBalance.fromJson(Map<String, dynamic> json) => _$WalletBalanceFromJson(json);

  Map<String, dynamic> toJson() => _$WalletBalanceToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

