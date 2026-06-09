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
**flashPriceMinor** | **int** | Flash-deal price in minor units; set only for products served by the /home/flash-deals rail. When present, render this as the price and price_minor as the strikethrough original.  | [optional] 
**freeShipping** | **bool** | When true, render the \"Kargo Bedava\" (free-shipping) badge (P-009). Sourced from the products.free_shipping flag.  | [optional] [default to false]
**favoritesCount** | **int** | Number of users who favorited this product — social proof by the heart on the card / PDP (P-004). Zero when none.  | [optional] [default to 0]
**isBestseller** | **bool** | When true, render the \"Çok Satan\" bestseller stamp on the card (G-3). Sourced from the products.is_bestseller flag.  | [optional] [default to false]
**basketDiscountPct** | **int** | Extra discount percentage applied at the basket — renders the \"Sepette %X İndirim\" pill (G-3). Omitted when null (no pill). Sourced from the products.basket_discount_pct column.  | [optional] 
**lowest30dPriceMinor** | **int** | Lowest price (minor units) applied in the last 30 days, for compliant display of price reductions (TR 6502 / EU Omnibus 2019/2161, P-030). Omitted when no in-window price history. The frontend shows the \"30 günün en düşük fiyatı\" line only when this is below price_minor — today it equals price_minor for every product (prices are immutable post-creation, so history has not yet diverged from the baseline).  | [optional] 
**cashbackPreview** | [**CashbackPreview**](CashbackPreview.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


