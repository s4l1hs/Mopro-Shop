# mopro_api.model.DeliveryEta

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**minDays** | **int** | Lower bound of the transit business-day estimate. | 
**maxDays** | **int** | Upper bound of the transit business-day estimate. | 
**confident** | **bool** | true when derived from a concrete origin×destination transit row; false when it is the conservative national fallback (unknown origin or destination, e.g. a guest with no address).  | 
**dispatchCity** | **String** | Normalized key of the seller's dispatch city, for an optional \"{city}'dan gönderilir\" line. Omitted when the origin is unknown.  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


