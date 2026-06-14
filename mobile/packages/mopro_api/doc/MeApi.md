# mopro_api.api.MeApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**changePassword**](MeApi.md#changepassword) | **POST** /me/password | Change the authenticated user&#39;s password
[**deleteMe**](MeApi.md#deleteme) | **DELETE** /me | Soft-delete the authenticated user account (KVKK / GDPR)
[**getMe**](MeApi.md#getme) | **GET** /me | Get authenticated user profile
[**getMyFitProfile**](MeApi.md#getmyfitprofile) | **GET** /me/fit-profile | Get the authenticated user&#39;s size-fit profile (size-fit phase 1)
[**putMyFitProfile**](MeApi.md#putmyfitprofile) | **PUT** /me/fit-profile | Create or replace the size-fit profile (idempotent upsert)
[**registerDevice**](MeApi.md#registerdevice) | **POST** /me/devices | Register a device FCM token for push notifications
[**unregisterDevice**](MeApi.md#unregisterdevice) | **DELETE** /me/devices/{id} | Remove a registered device (deregister push notifications)
[**updateMe**](MeApi.md#updateme) | **PATCH** /me | Update user profile fields


# **changePassword**
> changePassword(xIdempotencyKey, changePasswordRequest, xTraceId)

Change the authenticated user's password

Requires the current password in the body for verification. On success, all existing refresh tokens for the user are revoked (forces re-login on every other device). Rate limited by IP. Returns 401 `invalid_credentials` if old_password does not match; 422 `weak_password` if new_password fails strength rules. 

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getMeApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final ChangePasswordRequest changePasswordRequest = ; // ChangePasswordRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.changePassword(xIdempotencyKey, changePasswordRequest, xTraceId);
} catch on DioException (e) {
    print('Exception when calling MeApi->changePassword: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **changePasswordRequest** | [**ChangePasswordRequest**](ChangePasswordRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

void (empty response body)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteMe**
> deleteMe(xIdempotencyKey, deleteMeRequest, xTraceId)

Soft-delete the authenticated user account (KVKK / GDPR)

Requires step-up authentication (`stepUpAuth` security scheme). Account enters a 30-day grace period before permanent deletion. All active cashback plans are cancelled on confirmation. 

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getMeApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final DeleteMeRequest deleteMeRequest = ; // DeleteMeRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.deleteMe(xIdempotencyKey, deleteMeRequest, xTraceId);
} catch on DioException (e) {
    print('Exception when calling MeApi->deleteMe: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **deleteMeRequest** | [**DeleteMeRequest**](DeleteMeRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

void (empty response body)

### Authorization

[stepUpAuth](../README.md#stepUpAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMe**
> User getMe(xTraceId)

Get authenticated user profile

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getMeApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.getMe(xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MeApi->getMe: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**User**](User.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyFitProfile**
> FitProfileEnvelope getMyFitProfile(xTraceId)

Get the authenticated user's size-fit profile (size-fit phase 1)

Measurements are integer millimetres and are stored encrypted at rest (AES-GCM); a user without a profile gets 200 with exists=false. 

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getMeApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.getMyFitProfile(xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MeApi->getMyFitProfile: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**FitProfileEnvelope**](FitProfileEnvelope.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **putMyFitProfile**
> putMyFitProfile(fitProfile, xTraceId)

Create or replace the size-fit profile (idempotent upsert)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getMeApi();
final FitProfile fitProfile = ; // FitProfile | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.putMyFitProfile(fitProfile, xTraceId);
} catch on DioException (e) {
    print('Exception when calling MeApi->putMyFitProfile: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **fitProfile** | [**FitProfile**](FitProfile.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

void (empty response body)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **registerDevice**
> Device registerDevice(xIdempotencyKey, registerDeviceRequest, xTraceId)

Register a device FCM token for push notifications

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getMeApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final RegisterDeviceRequest registerDeviceRequest = ; // RegisterDeviceRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.registerDevice(xIdempotencyKey, registerDeviceRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MeApi->registerDevice: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **registerDeviceRequest** | [**RegisterDeviceRequest**](RegisterDeviceRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**Device**](Device.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **unregisterDevice**
> unregisterDevice(xIdempotencyKey, id, xTraceId)

Remove a registered device (deregister push notifications)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getMeApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.unregisterDevice(xIdempotencyKey, id, xTraceId);
} catch on DioException (e) {
    print('Exception when calling MeApi->unregisterDevice: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **id** | **int**|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

void (empty response body)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateMe**
> User updateMe(xIdempotencyKey, updateMeRequest, xTraceId)

Update user profile fields

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getMeApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final UpdateMeRequest updateMeRequest = ; // UpdateMeRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.updateMe(xIdempotencyKey, updateMeRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MeApi->updateMe: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **updateMeRequest** | [**UpdateMeRequest**](UpdateMeRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**User**](User.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

