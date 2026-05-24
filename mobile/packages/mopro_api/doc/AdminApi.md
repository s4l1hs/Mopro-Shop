# mopro_api.api.AdminApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createOrder**](AdminApi.md#createorder) | **POST** /orders | Create an order from a reservation (admin / internal)
[**createProduct**](AdminApi.md#createproduct) | **POST** /products | Create a new product listing (admin / seller onboarding)
[**getCategoryCommission**](AdminApi.md#getcategorycommission) | **GET** /categories/{id}/commission | Get live commission and KDV rates for a category + market pair
[**refundOrder**](AdminApi.md#refundorder) | **POST** /orders/{id}/refund | Trigger a full refund for a delivered order (admin only)


# **createOrder**
> Order createOrder(xIdempotencyKey, createOrderRequest, xTraceId)

Create an order from a reservation (admin / internal)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAdminApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final CreateOrderRequest createOrderRequest = ; // CreateOrderRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.createOrder(xIdempotencyKey, createOrderRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AdminApi->createOrder: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **createOrderRequest** | [**CreateOrderRequest**](CreateOrderRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**Order**](Order.md)

### Authorization

[adminAuth](../README.md#adminAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createProduct**
> Product createProduct(xIdempotencyKey, createProductRequest, xTraceId)

Create a new product listing (admin / seller onboarding)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAdminApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final CreateProductRequest createProductRequest = ; // CreateProductRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.createProduct(xIdempotencyKey, createProductRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AdminApi->createProduct: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **createProductRequest** | [**CreateProductRequest**](CreateProductRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**Product**](Product.md)

### Authorization

[adminAuth](../README.md#adminAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getCategoryCommission**
> CategoryCommission getCategoryCommission(id, xTraceId, market)

Get live commission and KDV rates for a category + market pair

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAdminApi();
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final String market = TR; // String | 

try {
    final response = api.getCategoryCommission(id, xTraceId, market);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AdminApi->getCategoryCommission: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **int**|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **market** | **String**|  | [optional] [default to 'TR']

### Return type

[**CategoryCommission**](CategoryCommission.md)

### Authorization

[adminAuth](../README.md#adminAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **refundOrder**
> refundOrder(xIdempotencyKey, id, refundOrderRequest, xTraceId)

Trigger a full refund for a delivered order (admin only)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAdminApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final int id = 789; // int | 
final RefundOrderRequest refundOrderRequest = ; // RefundOrderRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.refundOrder(xIdempotencyKey, id, refundOrderRequest, xTraceId);
} catch on DioException (e) {
    print('Exception when calling AdminApi->refundOrder: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **id** | **int**|  | 
 **refundOrderRequest** | [**RefundOrderRequest**](RefundOrderRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

void (empty response body)

### Authorization

[adminAuth](../README.md#adminAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

