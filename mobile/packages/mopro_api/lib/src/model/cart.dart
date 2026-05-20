//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/cart_item.dart';
import 'package:json_annotation/json_annotation.dart';

part 'cart.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Cart {
  /// Returns a new [Cart] instance.
  Cart({

    required  this.userId,

    required  this.items,

    required  this.subtotalMinor,

    required  this.subtotalCurrency,

    required  this.totalMonthlyCoinMinor,

    required  this.coinCurrency,
  });

  @JsonKey(
    
    name: r'user_id',
    required: true,
    includeIfNull: false,
  )


  final int userId;



  @JsonKey(
    
    name: r'items',
    required: true,
    includeIfNull: false,
  )


  final List<CartItem> items;



      /// Sum of price_minor × quantity across all items
  @JsonKey(
    
    name: r'subtotal_minor',
    required: true,
    includeIfNull: false,
  )


  final int subtotalMinor;



  @JsonKey(
    
    name: r'subtotal_currency',
    required: true,
    includeIfNull: false,
  )


  final String subtotalCurrency;



      /// Sum of monthly_coin_minor across all items
  @JsonKey(
    
    name: r'total_monthly_coin_minor',
    required: true,
    includeIfNull: false,
  )


  final int totalMonthlyCoinMinor;



  @JsonKey(
    
    name: r'coin_currency',
    required: true,
    includeIfNull: false,
  )


  final String coinCurrency;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Cart &&
      other.userId == userId &&
      other.items == items &&
      other.subtotalMinor == subtotalMinor &&
      other.subtotalCurrency == subtotalCurrency &&
      other.totalMonthlyCoinMinor == totalMonthlyCoinMinor &&
      other.coinCurrency == coinCurrency;

    @override
    int get hashCode =>
        userId.hashCode +
        items.hashCode +
        subtotalMinor.hashCode +
        subtotalCurrency.hashCode +
        totalMonthlyCoinMinor.hashCode +
        coinCurrency.hashCode;

  factory Cart.fromJson(Map<String, dynamic> json) => _$CartFromJson(json);

  Map<String, dynamic> toJson() => _$CartToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

