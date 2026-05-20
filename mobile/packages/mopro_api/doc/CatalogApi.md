# mopro_api.api.CatalogApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createProduct**](CatalogApi.md#createproduct) | **POST** /v1/products | Create a new product listing (admin / seller onboarding)
[**getCategoryCommission**](CatalogApi.md#getcategorycommission) | **GET** /v1/categories/{id}/commission | Get live commission and KDV rates for a category + market pair
[**getProduct**](CatalogApi.md#getproduct) | **GET** /v1/products/{id} | Get full product detail including variants and cashback preview
[**listCategories**](CatalogApi.md#listcategories) | **GET** /v1/categories | List all 42 product categories (locale-resolved names)
[**listProducts**](CatalogApi.md#listproducts) | **GET** /v1/products | List products with optional category filter, pagination, and sort


# **createProduct**
> Product createProduct(xIdempotencyKey, createProductRequest, xTraceId)

Create a new product listing (admin / seller onboarding)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getCatalogApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final CreateProductRequest createProductRequest = ; // CreateProductRequest | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.createProduct(xIdempotencyKey, createProductRequest, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CatalogApi->createProduct: $e\n');
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

final api = MoproApi().getCatalogApi();
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final String market = TR; // String | 

try {
    final response = api.getCategoryCommission(id, xTraceId, market);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CatalogApi->getCategoryCommission: $e\n');
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

# **getProduct**
> Product getProduct(id, xTraceId)

Get full product detail including variants and cashback preview

Server resolves `title` and `description` from `Accept-Language` header. `cashback_preview.monthly_coin_minor` is computed handler-layer: `round(variant.price_minor × commission_pct_bps/10000 × 5000/10000 / 12)`. Uses the lowest-priced active variant for the preview amount. `seller_name` is joined from the seller module (in-process, core-svc only). `image_urls` are CDN-resolved (not raw storage keys). 

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getCatalogApi();
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.getProduct(id, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CatalogApi->getProduct: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **int**|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**Product**](Product.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listCategories**
> ListCategories200Response listCategories(xTraceId)

List all 42 product categories (locale-resolved names)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getCatalogApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.listCategories(xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CatalogApi->listCategories: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**ListCategories200Response**](ListCategories200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listProducts**
> ListProducts200Response listProducts(xTraceId, categoryId, page, perPage, sort)

List products with optional category filter, pagination, and sort

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getCatalogApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final int categoryId = 789; // int | 
final int page = 56; // int | 
final int perPage = 56; // int | 
final String sort = sort_example; // String | 

try {
    final response = api.listProducts(xTraceId, categoryId, page, perPage, sort);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CatalogApi->listProducts: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **categoryId** | **int**|  | [optional] 
 **page** | **int**|  | [optional] [default to 1]
 **perPage** | **int**|  | [optional] [default to 20]
 **sort** | **String**|  | [optional] [default to 'recommended']

### Return type

[**ListProducts200Response**](ListProducts200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

