# mopro_api.model.Variant

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **int** |  | 
**sku** | **String** |  | 
**color** | **String** |  | [optional] 
**size** | **String** |  | [optional] 
**priceMinor** | **int** | Price in minor units (kuruş) | 
**priceCurrency** | **String** |  | 
**stock** | **int** |  | 
**imageUrls** | **List&lt;String&gt;** | CDN-resolved full URLs. Never raw storage keys. | 
**lowest30dPriceMinor** | **int** | Lowest price (minor units) applied to THIS variant in the last 30 days (TR 6502 / EU Omnibus, P-030). Per-variant so the PDP — which shows a specific selected variant — is accurate. Omitted when no in-window history; equals price_minor until the price changes (P-032).  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


