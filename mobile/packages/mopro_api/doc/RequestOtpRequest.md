# mopro_api.model.RequestOtpRequest

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**phone** | **String** | Turkish mobile number in E.164 format. Must start with +905. | 
**purpose** | **String** | OTP purpose. Omit (or send `login`) for initial authentication — the server treats an absent value as `login`. Use `step_up` only if you need a step-up OTP outside the authenticated step-up flow (`POST /auth/step-up/request`). Most clients should omit this field and rely on the server's `login` default.  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


