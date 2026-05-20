# mopro_api.api.AuthApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**logout**](AuthApi.md#logout) | **POST** /v1/auth/logout | Revoke the provided refresh token
[**refreshToken**](AuthApi.md#refreshtoken) | **POST** /v1/auth/token/refresh | Exchange a refresh token for a new token pair
[**requestOtp**](AuthApi.md#requestotp) | **POST** /v1/auth/otp/request | Request a one-time password via SMS
[**stepUp**](AuthApi.md#stepup) | **POST** /v1/auth/step-up | Exchange access token + fresh OTP for a step-up token (TTL 5 min)
[**verifyOtp**](AuthApi.md#verifyotp) | **POST** /v1/auth/otp/verify | Verify OTP and issue access + refresh token pair


# **logout**
> logout(xIdempotencyKey, refreshTokenRequest, xTraceId)

Revoke the provided refresh token

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAuthApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final RefreshTokenRequest refreshTokenRequest = ; // RefreshTokenRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.logout(xIdempotencyKey, refreshTokenRequest, xTraceId);
} catch on DioException (e) {
    print('Exception when calling AuthApi->logout: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **refreshTokenRequest** | [**RefreshTokenRequest**](RefreshTokenRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

void (empty response body)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **refreshToken**
> TokenPair refreshToken(xIdempotencyKey, refreshTokenRequest, xTraceId)

Exchange a refresh token for a new token pair

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAuthApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final RefreshTokenRequest refreshTokenRequest = ; // RefreshTokenRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.refreshToken(xIdempotencyKey, refreshTokenRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthApi->refreshToken: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **refreshTokenRequest** | [**RefreshTokenRequest**](RefreshTokenRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**TokenPair**](TokenPair.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **requestOtp**
> requestOtp(requestOtpRequest, xTraceId)

Request a one-time password via SMS

Dispatches a 6-digit OTP to the provided phone number. Rate-limited per phone: max 3 requests per 5 minutes. X-Idempotency-Key is NOT honored here — each call always dispatches a new OTP to avoid replay-suppression attacks. 

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAuthApi();
final RequestOtpRequest requestOtpRequest = ; // RequestOtpRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.requestOtp(requestOtpRequest, xTraceId);
} catch on DioException (e) {
    print('Exception when calling AuthApi->requestOtp: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **requestOtpRequest** | [**RequestOtpRequest**](RequestOtpRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **stepUp**
> StepUpTokenResponse stepUp(xIdempotencyKey, stepUpRequest, xTraceId)

Exchange access token + fresh OTP for a step-up token (TTL 5 min)

Call this after receiving `403 step_up_required`. The caller must have already called `/v1/auth/otp/request` to obtain a fresh OTP for the currently authenticated phone number. 

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAuthApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final StepUpRequest stepUpRequest = ; // StepUpRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.stepUp(xIdempotencyKey, stepUpRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthApi->stepUp: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **stepUpRequest** | [**StepUpRequest**](StepUpRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**StepUpTokenResponse**](StepUpTokenResponse.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **verifyOtp**
> TokenPair verifyOtp(xIdempotencyKey, verifyOtpRequest, xTraceId)

Verify OTP and issue access + refresh token pair

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAuthApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final VerifyOtpRequest verifyOtpRequest = ; // VerifyOtpRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.verifyOtp(xIdempotencyKey, verifyOtpRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthApi->verifyOtp: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **verifyOtpRequest** | [**VerifyOtpRequest**](VerifyOtpRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**TokenPair**](TokenPair.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

