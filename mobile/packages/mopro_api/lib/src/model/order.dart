//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/order_item.dart';
import 'package:json_annotation/json_annotation.dart';

part 'order.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Order {
  /// Returns a new [Order] instance.
  Order({

    required  this.id,

    required  this.userId,

    required  this.status,

    required  this.items,

    required  this.totalMinor,

    required  this.currency,

     this.cargoOption,

     this.cashbackUnlockAt,

     this.deliveredAt,

    required  this.createdAt,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'user_id',
    required: true,
    includeIfNull: false,
  )


  final int userId;



  @JsonKey(
    
    name: r'status',
    required: true,
    includeIfNull: false,
  )


  final OrderStatusEnum status;



  @JsonKey(
    
    name: r'items',
    required: true,
    includeIfNull: false,
  )


  final List<OrderItem> items;



  @JsonKey(
    
    name: r'total_minor',
    required: true,
    includeIfNull: false,
  )


  final int totalMinor;



  @JsonKey(
    
    name: r'currency',
    required: true,
    includeIfNull: false,
  )


  final String currency;



  @JsonKey(
    
    name: r'cargo_option',
    required: false,
    includeIfNull: false,
  )


  final OrderCargoOptionEnum? cargoOption;



      /// When the cashback plan becomes active. Computed as delivered_at + 3 business days (TR calendar). Null until the order is delivered. 
  @JsonKey(
    
    name: r'cashback_unlock_at',
    required: false,
    includeIfNull: false,
  )


  final DateTime? cashbackUnlockAt;



  @JsonKey(
    
    name: r'delivered_at',
    required: false,
    includeIfNull: false,
  )


  final DateTime? deliveredAt;



  @JsonKey(
    
    name: r'created_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime createdAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Order &&
      other.id == id &&
      other.userId == userId &&
      other.status == status &&
      other.items == items &&
      other.totalMinor == totalMinor &&
      other.currency == currency &&
      other.cargoOption == cargoOption &&
      other.cashbackUnlockAt == cashbackUnlockAt &&
      other.deliveredAt == deliveredAt &&
      other.createdAt == createdAt;

    @override
    int get hashCode =>
        id.hashCode +
        userId.hashCode +
        status.hashCode +
        items.hashCode +
        totalMinor.hashCode +
        currency.hashCode +
        cargoOption.hashCode +
        cashbackUnlockAt.hashCode +
        deliveredAt.hashCode +
        createdAt.hashCode;

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);

  Map<String, dynamic> toJson() => _$OrderToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum OrderStatusEnum {
@JsonValue(r'pending')
pending(r'pending'),
@JsonValue(r'confirmed')
confirmed(r'confirmed'),
@JsonValue(r'preparing')
preparing(r'preparing'),
@JsonValue(r'shipped')
shipped(r'shipped'),
@JsonValue(r'delivered')
delivered(r'delivered'),
@JsonValue(r'cancelled')
cancelled(r'cancelled'),
@JsonValue(r'refunded')
refunded(r'refunded');

const OrderStatusEnum(this.value);

final String value;

@override
String toString() => value;
}



enum OrderCargoOptionEnum {
@JsonValue(r'aras')
aras(r'aras'),
@JsonValue(r'yurtici')
yurtici(r'yurtici'),
@JsonValue(r'surat')
surat(r'surat'),
@JsonValue(r'mng')
mng(r'mng'),
@JsonValue(r'hepsijet')
hepsijet(r'hepsijet'),
@JsonValue(r'ptt')
ptt(r'ptt');

const OrderCargoOptionEnum(this.value);

final String value;

@override
String toString() => value;
}


