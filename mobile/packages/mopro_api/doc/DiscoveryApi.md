# mopro_api.api.DiscoveryApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**listBanners**](DiscoveryApi.md#listbanners) | **GET** /banners | Promotional banners for a given placement
[**listRecommendations**](DiscoveryApi.md#listrecommendations) | **GET** /recommendations | Personalised product recommendations for the authenticated user


# **listBanners**
> ListBanners200Response listBanners(xTraceId, placement)

Promotional banners for a given placement

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getDiscoveryApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final String placement = placement_example; // String | 

try {
    final response = api.listBanners(xTraceId, placement);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DiscoveryApi->listBanners: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **placement** | **String**|  | [optional] [default to 'home']

### Return type

[**ListBanners200Response**](ListBanners200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listRecommendations**
> ListRecommendations200Response listRecommendations(xTraceId)

Personalised product recommendations for the authenticated user

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getDiscoveryApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.listRecommendations(xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DiscoveryApi->listRecommendations: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**ListRecommendations200Response**](ListRecommendations200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

