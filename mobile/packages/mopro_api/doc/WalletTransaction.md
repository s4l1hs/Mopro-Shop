# mopro_api.model.WalletTransaction

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **int** |  | 
**type** | **String** |  | 
**amountMinor** | **int** |  | 
**currency** | **String** |  | 
**description** | **String** |  | [optional] 
**referenceId** | **int** | plan_id for cashback credits; payout_id for debits. Null for manual adjustments. | [optional] 
**referenceType** | **String** |  | [optional] 
**occurredAt** | [**DateTime**](DateTime.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


