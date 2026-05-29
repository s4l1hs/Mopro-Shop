# mopro_api.model.ProductSummary

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **int** |  | 
**sellerId** | **int** |  | 
**categoryId** | **int** |  | 
**brand** | **String** |  | 
**status** | **String** |  | 
**title** | **String** | Locale-resolved | 
**priceMinor** | **int** | Lowest-priced active variant price in minor units | 
**priceCurrency** | **String** |  | 
**coverImageUrl** | **String** | First image URL of the lowest-priced variant | [optional] 
**originalPriceMinor** | **int** | MSRP in minor units. When set and greater than price_minor, render with strikethrough; backend also emits discount_pct.  | [optional] 
**discountPct** | **int** | Server-computed discount % when original_price_minor > price_minor. Render as red %-badge next to the strikethrough.  | [optional] 
**ratingAvg** | **double** | Average review rating (0.0–5.0); null when rating_count = 0 | [optional] 
**ratingCount** | **int** | Number of reviews aggregated into rating_avg | [optional] [default to 0]
**cashbackPreview** | [**CashbackPreview**](CashbackPreview.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


