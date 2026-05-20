# mopro_api.model.ErrorEnvelopeError

## Load the model package
```dart
import 'package:mopro_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**code** | **String** | Machine-readable error slug | 
**message** | **String** | Human-readable error message (locale from Accept-Language) | 
**traceId** | **String** | Request trace ID. Echoes X-Trace-Id or server-generated UUID. | 
**fields** | [**List&lt;FieldError&gt;**](FieldError.md) | Per-field validation errors. Present only for 422 responses. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


