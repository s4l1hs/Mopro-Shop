# mopro_api.api.CatalogApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createProduct**](CatalogApi.md#createproduct) | **POST** /products | Create a new product listing (admin / seller onboarding)
[**getCategoryCommission**](CatalogApi.md#getcategorycommission) | **GET** /categories/{id}/commission | Get live commission and KDV rates for a category + market pair
[**getProduct**](CatalogApi.md#getproduct) | **GET** /products/{id} | Get full product detail including variants and cashback preview
[**listCategories**](CatalogApi.md#listcategories) | **GET** /categories | List all 42 product categories (locale-resolved names)
[**listProducts**](CatalogApi.md#listproducts) | **GET** /products | List products with category filter, price/brand/rating/shipping filters, pagination, and sort


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
> ListCategories200Response listCategories(xTraceId, depth)

List all 42 product categories (locale-resolved names)

Returns a flat list of active categories; each row carries `parent_id` for client-side tree reconstruction. Default behavior returns all depths (mobile callers rely on this — do not change).  Optional `depth` query param filters to categories whose chain length to a root parent is at most N (root=0, direct children=1, …). Used by the desktop mega menu (Session 4c §3) to pre-load the bar + subcategory leaves in one call. Hard ceiling: 1000 nodes per response. 

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getCatalogApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final int depth = 56; // int | Filter chain length from root parent. Valid range 1..3. Omitting the param returns all depths (historical behavior). 

try {
    final response = api.listCategories(xTraceId, depth);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CatalogApi->listCategories: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **depth** | **int**| Filter chain length from root parent. Valid range 1..3. Omitting the param returns all depths (historical behavior).  | [optional] 

### Return type

[**ListCategories200Response**](ListCategories200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listProducts**
> ListProducts200Response listProducts(xTraceId, categoryId, page, perPage, minPrice, maxPrice, brand, rating, freeShipping, inStock, sort)

List products with category filter, price/brand/rating/shipping filters, pagination, and sort

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getCatalogApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final int categoryId = 789; // int | Scope results to a category (optional on /search).
final int page = 56; // int | 
final int perPage = 56; // int | 
final int minPrice = 789; // int | Minimum price in minor units (filters the displayed/lowest variant price).
final int maxPrice = 789; // int | Maximum price in minor units (filters the displayed/lowest variant price).
final List<String> brand = ; // List<String> | Repeatable; matches any of the given brands (?brand=Nike&brand=Adidas).
final int rating = 56; // int | Minimum average rating (products with rating_avg >= this).
final bool freeShipping = true; // bool | When true, only products flagged free-shipping.
final bool inStock = true; // bool | When true, only products with at least one in-stock variant.
final String sort = sort_example; // String | Sort order. Unknown/unsupported tokens fall back to `recommended`. `bestseller` orders by global popularity (P-029); it degrades to `recommended` until the analytics popularity projection has data. 

try {
    final response = api.listProducts(xTraceId, categoryId, page, perPage, minPrice, maxPrice, brand, rating, freeShipping, inStock, sort);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CatalogApi->listProducts: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **categoryId** | **int**| Scope results to a category (optional on /search). | [optional] 
 **page** | **int**|  | [optional] [default to 1]
 **perPage** | **int**|  | [optional] [default to 20]
 **minPrice** | **int**| Minimum price in minor units (filters the displayed/lowest variant price). | [optional] 
 **maxPrice** | **int**| Maximum price in minor units (filters the displayed/lowest variant price). | [optional] 
 **brand** | [**List&lt;String&gt;**](String.md)| Repeatable; matches any of the given brands (?brand=Nike&brand=Adidas). | [optional] 
 **rating** | **int**| Minimum average rating (products with rating_avg >= this). | [optional] 
 **freeShipping** | **bool**| When true, only products flagged free-shipping. | [optional] 
 **inStock** | **bool**| When true, only products with at least one in-stock variant. | [optional] 
 **sort** | **String**| Sort order. Unknown/unsupported tokens fall back to `recommended`. `bestseller` orders by global popularity (P-029); it degrades to `recommended` until the analytics popularity projection has data.  | [optional] [default to 'recommended']

### Return type

[**ListProducts200Response**](ListProducts200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

