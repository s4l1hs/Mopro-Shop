# mopro_api.model.Product

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **int** |  | 
**sellerId** | **int** |  | 
**sellerName** | **String** |  | 
**sellerOfficial** | **bool** | When true, the seller is an official/verified storefront — render the \"Resmi Satıcı\" badge on the PDP seller card (PD-04). From seller_schema.sellers.is_official, resolved in-process (no JOIN, §5).  | [optional] [default to false]
**sellerSlug** | **String** | URL-safe identifier for the seller; used to deep-link to the seller storefront at /sellers/:slug. Null when the product's seller_id does not resolve to an active seller (legacy/platform-direct or suspended).  | [optional] 
**categoryId** | **int** |  | 
**brand** | **String** |  | 
**status** | **String** |  | 
**title** | **String** | Locale-resolved from Accept-Language header | 
**description** | **String** | Locale-resolved. Falls back to tr-TR if requested locale unavailable. | 
**variants** | [**List&lt;Variant&gt;**](Variant.md) |  | 
**attributes** | [**List&lt;ProductAttribute&gt;**](ProductAttribute.md) | Normalized product attributes (PLP-13) for the specs tab (PD-01) — slug + locale-resolved name + value(s). Empty array when the product has no attributes.  | 
**cashbackPreview** | [**CashbackPreview**](CashbackPreview.md) |  | 
**deliveryEta** | [**DeliveryEta**](DeliveryEta.md) | Pre-purchase delivery estimate (P-034). Null when no estimate is available. Not a delivery SLA — `confident=false` ranges are fallback estimates the UI hedges as \"tahmini\".  | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | 
**basketDiscountPct** | **int** | PD-03: the whole-percent seller-funded \"Sepette %X İndirim\" (CT-09). The SAME products.basket_discount_pct snapshotted onto the order at checkout → display==charge. Omitted/null when 0 (no discount).  | [optional] 
**sellerRatingAvg** | **double** | PD-04: the seller's aggregate review rating (mean of their products' reviews). Null when the seller has no reviews → the card shows no rating.  | [optional] 
**sellerRatingCount** | **int** | PD-04: number of reviews backing seller_rating_avg (0 = none).  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


