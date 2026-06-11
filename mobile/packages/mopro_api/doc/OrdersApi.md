# mopro_api.api.OrdersApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancelOrder**](OrdersApi.md#cancelorder) | **POST** /orders/{id}/cancel | Cancel an order (only while in pending_payment/paid status)
[**checkout**](OrdersApi.md#checkout) | **POST** /orders/checkout | Atomically reserve cart → create order → initiate PSP payment
[**createOrder**](OrdersApi.md#createorder) | **POST** /orders | Create an order from a reservation (admin / internal)
[**createReturn**](OrdersApi.md#createreturn) | **POST** /orders/{id}/returns | Submit a return request for delivered order items
[**getOrder**](OrdersApi.md#getorder) | **GET** /orders/{id} | Get order detail
[**listOrders**](OrdersApi.md#listorders) | **GET** /orders | List the authenticated user&#39;s orders
[**listReturns**](OrdersApi.md#listreturns) | **GET** /orders/{id}/returns | List return requests for an order
[**refundOrder**](OrdersApi.md#refundorder) | **POST** /orders/{id}/refund | Trigger a full refund for a delivered order (admin only)


# **cancelOrder**
> cancelOrder(xIdempotencyKey, id, xTraceId)

Cancel an order (only while in pending_payment/paid status)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getOrdersApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.cancelOrder(xIdempotencyKey, id, xTraceId);
} catch on DioException (e) {
    print('Exception when calling OrdersApi->cancelOrder: $e\n');
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

# **checkout**
> CheckoutResponse checkout(xIdempotencyKey, checkoutRequest, xTraceId)

Atomically reserve cart → create order → initiate PSP payment

Single-shot convenience endpoint for the mobile checkout flow. Internally calls cart.Reserve → order.Create → payment.Initiate. Returns immediately with redirect_url for 3DS if required, or order details for non-3DS payment methods. 

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getOrdersApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final CheckoutRequest checkoutRequest = ; // CheckoutRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.checkout(xIdempotencyKey, checkoutRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling OrdersApi->checkout: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **checkoutRequest** | [**CheckoutRequest**](CheckoutRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**CheckoutResponse**](CheckoutResponse.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createOrder**
> Order createOrder(xIdempotencyKey, createOrderRequest, xTraceId)

Create an order from a reservation (admin / internal)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getOrdersApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final CreateOrderRequest createOrderRequest = ; // CreateOrderRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.createOrder(xIdempotencyKey, createOrderRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling OrdersApi->createOrder: $e\n');
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

# **createReturn**
> ModelReturn createReturn(xIdempotencyKey, id, returnRequest, xTraceId)

Submit a return request for delivered order items

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getOrdersApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final int id = 789; // int | 
final ReturnRequest returnRequest = ; // ReturnRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.createReturn(xIdempotencyKey, id, returnRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling OrdersApi->createReturn: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **id** | **int**|  | 
 **returnRequest** | [**ReturnRequest**](ReturnRequest.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**ModelReturn**](ModelReturn.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getOrder**
> Order getOrder(id, xTraceId)

Get order detail

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getOrdersApi();
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.getOrder(id, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling OrdersApi->getOrder: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **int**|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**Order**](Order.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listOrders**
> ListOrders200Response listOrders(xTraceId, status, page, perPage)

List the authenticated user's orders

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getOrdersApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final String status = status_example; // String | 
final int page = 56; // int | 
final int perPage = 56; // int | 

try {
    final response = api.listOrders(xTraceId, status, page, perPage);
    print(response);
} catch on DioException (e) {
    print('Exception when calling OrdersApi->listOrders: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **status** | **String**|  | [optional] 
 **page** | **int**|  | [optional] [default to 1]
 **perPage** | **int**|  | [optional] [default to 20]

### Return type

[**ListOrders200Response**](ListOrders200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listReturns**
> ListReturns200Response listReturns(id, xTraceId)

List return requests for an order

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getOrdersApi();
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.listReturns(id, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling OrdersApi->listReturns: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **int**|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**ListReturns200Response**](ListReturns200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

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

final api = MoproApi().getOrdersApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final int id = 789; // int | 
final RefundOrderRequest refundOrderRequest = ; // RefundOrderRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.refundOrder(xIdempotencyKey, id, refundOrderRequest, xTraceId);
} catch on DioException (e) {
    print('Exception when calling OrdersApi->refundOrder: $e\n');
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

