# mopro_api.model.CashbackPlan

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **int** |  | 
**orderId** | **int** |  | 
**productId** | **int** |  | 
**productTitle** | **String** |  | 
**productImageUrl** | **String** |  | [optional] 
**monthlyAmountMinor** | **int** |  | 
**currency** | **String** |  | 
**status** | **String** |  | 
**startDate** | [**DateTime**](DateTime.md) | ISO 8601 date (YYYY-MM-DD). First instalment paid on or after this date. | 
**referenceInterestRateBps** | **int** | Reference rate in basis points (5000 = 50%). Frozen at plan creation time per the v6 perpetual cashback formula. Existing plans retain their original rate even if the platform's reference rate changes later. See LEDGER_GUIDE.md §3.4 for the formula derivation.  | 
**createdAt** | [**DateTime**](DateTime.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


