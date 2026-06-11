# mopro_api.model.Order

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **int** |  | 
**userId** | **int** |  | 
**status** | **String** |  | 
**items** | [**List&lt;OrderItem&gt;**](OrderItem.md) |  | 
**totalMinor** | **int** |  | 
**currency** | **String** |  | 
**cargoOption** | **String** |  | [optional] 
**cashbackUnlockAt** | [**DateTime**](DateTime.md) | When the cashback plan becomes active. Computed as delivered_at + 3 business days (TR calendar). Null until the order is delivered.  | [optional] 
**deliveredAt** | [**DateTime**](DateTime.md) |  | [optional] 
**deliveryAddress** | [**DeliveryAddress**](DeliveryAddress.md) | Immutable ship-to snapshot captured at checkout (OR-02). Null for legacy orders created before address capture. A frozen copy, NOT a live reference to the user's (mutable) saved address.  | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


