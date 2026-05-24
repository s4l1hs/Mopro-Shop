# mopro_api.api.SellerApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getSellerOrderBreakdown**](SellerApi.md#getsellerorderbreakdown) | **GET** /seller/orders/{id}/breakdown | Seller transparency breakdown for a specific order


# **getSellerOrderBreakdown**
> SellerOrderBreakdown getSellerOrderBreakdown(id, xMoproSellerId, xTraceId)

Seller transparency breakdown for a specific order

Returns per-item commission, KDV, service fee (always 0 for Mopro), and net payout amounts. Used by the seller panel web app.  **Current auth:** Requires `X-Mopro-Seller-Id` header containing the seller's integer ID. Phase 4.2a replaces this with seller JWT (`bearerAuth`). 

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getSellerApi();
final int id = 789; // int | 
final String xMoproSellerId = xMoproSellerId_example; // String | Seller ID header. Replaced by JWT in Phase 4.2a.
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.getSellerOrderBreakdown(id, xMoproSellerId, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SellerApi->getSellerOrderBreakdown: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **int**|  | 
 **xMoproSellerId** | **String**| Seller ID header. Replaced by JWT in Phase 4.2a. | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**SellerOrderBreakdown**](SellerOrderBreakdown.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

