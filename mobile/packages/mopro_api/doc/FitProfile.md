# mopro_api.model.FitProfile

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**chestMm** | **int** |  | [optional] 
**waistMm** | **int** |  | [optional] 
**hipMm** | **int** |  | [optional] 
**inseamMm** | **int** |  | [optional] 
**heightMm** | **int** |  | [optional] 
**weightG** | **int** | Weight in grams (basic-estimation input; encrypted at rest). | [optional] 
**gender** | **String** | female | male | unspecified (basic-estimation input, NOT a measurement). unspecified disables basic estimation for the user.  | [optional] 
**fitPref** | **String** | regular | loose | tight (between-sizes tiebreak). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


