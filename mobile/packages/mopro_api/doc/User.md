# mopro_api.model.User

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **int** |  | 
**phone** | **String** |  | 
**nameFirst** | **String** |  | [optional] 
**nameLast** | **String** |  | [optional] 
**email** | **String** |  | [optional] 
**locale** | **String** |  | 
**createdAt** | [**DateTime**](DateTime.md) |  | 
**updatedAt** | [**DateTime**](DateTime.md) |  | 
**sellerBinding** | [**SellerBinding**](SellerBinding.md) | The user's seller-account binding, or null when the user is not bound to an active seller. Drives client-side seller-role detection.  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


