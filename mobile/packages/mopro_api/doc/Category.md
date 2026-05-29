# mopro_api.model.Category

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **int** |  | 
**name** | **String** | Locale-resolved category name | 
**slug** | **String** |  | 
**parentId** | **int** |  | [optional] 
**iconUrl** | **String** |  | [optional] 
**commissionPctBps** | **int** | Commission rate in basis points (e.g. 1500 = 15%) | 
**promoSlot** | [**CategoryPromoSlot**](CategoryPromoSlot.md) | Optional promo card surfaced ONLY on top-level categories (parent_id IS NULL). Always null on subcategories and leaves. Used by the desktop mega menu's 3+1 layout (Session 4d §3); mobile clients can ignore. Malformed JSON in the underlying storage is normalized to null + a warning log by the server.  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


