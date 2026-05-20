//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'wallet_transaction.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class WalletTransaction {
  /// Returns a new [WalletTransaction] instance.
  WalletTransaction({

    required  this.id,

    required  this.type,

    required  this.amountMinor,

    required  this.currency,

     this.description,

     this.referenceId,

     this.referenceType,

    required  this.occurredAt,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'type',
    required: true,
    includeIfNull: false,
  )


  final WalletTransactionTypeEnum type;



  @JsonKey(
    
    name: r'amount_minor',
    required: true,
    includeIfNull: false,
  )


  final int amountMinor;



  @JsonKey(
    
    name: r'currency',
    required: true,
    includeIfNull: false,
  )


  final String currency;



  @JsonKey(
    
    name: r'description',
    required: false,
    includeIfNull: false,
  )


  final String? description;



      /// plan_id for cashback credits; payout_id for debits. Null for manual adjustments.
  @JsonKey(
    
    name: r'reference_id',
    required: false,
    includeIfNull: false,
  )


  final int? referenceId;



  @JsonKey(
    
    name: r'reference_type',
    required: false,
    includeIfNull: false,
  )


  final WalletTransactionReferenceTypeEnum? referenceType;



  @JsonKey(
    
    name: r'occurred_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime occurredAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is WalletTransaction &&
      other.id == id &&
      other.type == type &&
      other.amountMinor == amountMinor &&
      other.currency == currency &&
      other.description == description &&
      other.referenceId == referenceId &&
      other.referenceType == referenceType &&
      other.occurredAt == occurredAt;

    @override
    int get hashCode =>
        id.hashCode +
        type.hashCode +
        amountMinor.hashCode +
        currency.hashCode +
        description.hashCode +
        referenceId.hashCode +
        referenceType.hashCode +
        occurredAt.hashCode;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) => _$WalletTransactionFromJson(json);

  Map<String, dynamic> toJson() => _$WalletTransactionToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum WalletTransactionTypeEnum {
@JsonValue(r'credit')
credit(r'credit'),
@JsonValue(r'debit')
debit(r'debit');

const WalletTransactionTypeEnum(this.value);

final String value;

@override
String toString() => value;
}



enum WalletTransactionReferenceTypeEnum {
@JsonValue(r'cashback_payment')
cashbackPayment(r'cashback_payment'),
@JsonValue(r'payout')
payout(r'payout'),
@JsonValue(r'adjustment')
adjustment(r'adjustment');

const WalletTransactionReferenceTypeEnum(this.value);

final String value;

@override
String toString() => value;
}


