# mopro_api.api.CashbackApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getCashbackPlan**](CashbackApi.md#getcashbackplan) | **GET** /v1/cashback/plans/{id} | Get a single cashback plan
[**listCashbackPayments**](CashbackApi.md#listcashbackpayments) | **GET** /v1/cashback/plans/{id}/payments | List monthly payment history for a cashback plan (cursor-paginated)
[**listCashbackPlans**](CashbackApi.md#listcashbackplans) | **GET** /v1/cashback/plans | List the authenticated user&#39;s perpetual cashback plans


# **getCashbackPlan**
> CashbackPlan getCashbackPlan(id, xTraceId)

Get a single cashback plan

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getCashbackApi();
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.getCashbackPlan(id, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CashbackApi->getCashbackPlan: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **int**|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**CashbackPlan**](CashbackPlan.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listCashbackPayments**
> ListCashbackPayments200Response listCashbackPayments(id, xTraceId, cursor, limit)

List monthly payment history for a cashback plan (cursor-paginated)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getCashbackApi();
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final String cursor = cursor_example; // String | 
final int limit = 56; // int | 

try {
    final response = api.listCashbackPayments(id, xTraceId, cursor, limit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CashbackApi->listCashbackPayments: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **int**|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **cursor** | **String**|  | [optional] 
 **limit** | **int**|  | [optional] [default to 24]

### Return type

[**ListCashbackPayments200Response**](ListCashbackPayments200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listCashbackPlans**
> ListCashbackPlans200Response listCashbackPlans(xTraceId, status, cursor, limit)

List the authenticated user's perpetual cashback plans

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getCashbackApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final String status = status_example; // String | 
final String cursor = cursor_example; // String | 
final int limit = 56; // int | 

try {
    final response = api.listCashbackPlans(xTraceId, status, cursor, limit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CashbackApi->listCashbackPlans: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **status** | **String**|  | [optional] 
 **cursor** | **String**|  | [optional] 
 **limit** | **int**|  | [optional] [default to 20]

### Return type

[**ListCashbackPlans200Response**](ListCashbackPlans200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

