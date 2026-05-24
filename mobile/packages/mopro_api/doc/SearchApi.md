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
> ListProducts200Response search(q, xTraceId, categoryId, minPrice, maxPrice, sort, page, perPage)

Full-text product search with filters

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getSearchApi();
final String q = q_example; // String | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final int categoryId = 789; // int | 
final int minPrice = 789; // int | 
final int maxPrice = 789; // int | 
final String sort = sort_example; // String | 
final int page = 56; // int | 
final int perPage = 56; // int | 

try {
    final response = api.search(q, xTraceId, categoryId, minPrice, maxPrice, sort, page, perPage);
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
 **categoryId** | **int**|  | [optional] 
 **minPrice** | **int**|  | [optional] 
 **maxPrice** | **int**|  | [optional] 
 **sort** | **String**|  | [optional] [default to 'recommended']
 **page** | **int**|  | [optional] [default to 1]
 **perPage** | **int**|  | [optional] [default to 20]

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

