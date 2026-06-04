# mopro_api.api.SearchApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**search**](SearchApi.md#search) | **GET** /search | Full-text product search with filters
[**searchSuggest**](SearchApi.md#searchsuggest) | **GET** /search/suggest | Autocomplete suggestions (debounce 250 ms on client)
[**searchTrending**](SearchApi.md#searchtrending) | **GET** /search/trending | Current trending search terms


# **search**
> ListProducts200Response search(q, xTraceId, categoryId, page, perPage, minPrice, maxPrice, brand, rating, freeShipping, inStock, sort)

Full-text product search with filters

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getSearchApi();
final String q = q_example; // String | 
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
    final response = api.search(q, xTraceId, categoryId, page, perPage, minPrice, maxPrice, brand, rating, freeShipping, inStock, sort);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SearchApi->search: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **q** | **String**|  | 
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

# **searchSuggest**
> SearchSuggest200Response searchSuggest(q, xTraceId)

Autocomplete suggestions (debounce 250 ms on client)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getSearchApi();
final String q = q_example; // String | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.searchSuggest(q, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SearchApi->searchSuggest: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **q** | **String**|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**SearchSuggest200Response**](SearchSuggest200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **searchTrending**
> SearchTrending200Response searchTrending(xTraceId)

Current trending search terms

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getSearchApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.searchTrending(xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SearchApi->searchTrending: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**SearchTrending200Response**](SearchTrending200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

