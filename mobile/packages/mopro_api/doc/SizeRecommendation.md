# mopro_api.model.SizeRecommendation

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**status** | **String** | ok | no_profile | incomplete_profile | no_chart | 
**garmentType** | **String** | top | bottom | dress | skirt | outerwear (chart key). | [optional] 
**size** | **String** |  | [optional] 
**signal** | **String** | true_to_size | between | size_up | size_down | [optional] 
**betweenLower** | **String** |  | [optional] 
**betweenUpper** | **String** |  | [optional] 
**missing** | **List&lt;String&gt;** |  | [optional] 
**confidence** | **String** | detailed (every relevant measurement was a real profile value) | basic (>=1 was estimated from height/weight/gender → show the approximate warning). Empty for non-ok statuses.  | [optional] 
**estimated** | **List&lt;String&gt;** | Relevant measurements synthesized from height/weight/gender. | [optional] 
**chartApproximate** | **bool** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


