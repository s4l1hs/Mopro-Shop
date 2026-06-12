# mopro_api.model.Membership

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**tier** | **String** | Current tier code (e.g. classic, gold, elite). | 
**rank** | **int** | 1-based ladder position of the current tier. | 
**windowDays** | **int** | Rolling qualification window length in days. | 
**spendMinor** | **int** | Delivered-order spend in the window, minor units. | 
**orderCount** | **int** | Delivered orders in the window. | 
**currency** | **String** | Currency of spend_minor and the thresholds. | 
**nextTier** | **String** | Next tier code; omitted at the top tier. | [optional] 
**nextMinSpendMinor** | **int** | Spend threshold of the next tier, minor units. | [optional] 
**nextMinOrders** | **int** | Order-count threshold of the next tier. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


