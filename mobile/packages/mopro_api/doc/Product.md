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
**categoryId** | **int** |  | 
**brand** | **String** |  | 
**status** | **String** |  | 
**title** | **String** | Locale-resolved from Accept-Language header | 
**description** | **String** | Locale-resolved. Falls back to tr-TR if requested locale unavailable. | 
**variants** | [**List&lt;Variant&gt;**](Variant.md) |  | 
**cashbackPreview** | [**CashbackPreview**](CashbackPreview.md) |  | 
**createdAt** | [**DateTime**](DateTime.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


