# mopro_api.model.Cart

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**userId** | **int** |  | 
**items** | [**List&lt;CartItem&gt;**](CartItem.md) |  | 
**subtotalMinor** | **int** | Sum of price_minor × quantity across all items | 
**subtotalCurrency** | **String** |  | 
**totalMonthlyCoinMinor** | **int** | Sum of monthly_coin_minor across all items | 
**coinCurrency** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


