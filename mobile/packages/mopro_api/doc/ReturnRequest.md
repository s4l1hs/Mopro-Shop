# mopro_api.model.ReturnRequest

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**reason** | **String** |  | 
**description** | **String** |  | [optional] 
**items** | [**List&lt;ReturnRequestItemsInner&gt;**](ReturnRequestItemsInner.md) | Specific items and quantities to return. If absent, full order return. | [optional] 
**photoKeys** | **List&lt;String&gt;** | RT-03: evidence photo storage keys (from POST /uploads/photos). Stored on the return; the detail serves them back as CDN urls (photo_urls).  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


