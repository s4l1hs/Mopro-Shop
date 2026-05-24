# mopro_api.api.AddressApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createAddress**](AddressApi.md#createaddress) | **POST** /addresses | Add a new delivery address
[**deleteAddress**](AddressApi.md#deleteaddress) | **DELETE** /addresses/{id} | Delete an address
[**listAddresses**](AddressApi.md#listaddresses) | **GET** /addresses | List the authenticated user&#39;s delivery addresses
[**updateAddress**](AddressApi.md#updateaddress) | **PUT** /addresses/{id} | Update an existing address


# **createAddress**
> Address createAddress(xIdempotencyKey, addressInput, xTraceId)

Add a new delivery address

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAddressApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final AddressInput addressInput = ; // AddressInput | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.createAddress(xIdempotencyKey, addressInput, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AddressApi->createAddress: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **addressInput** | [**AddressInput**](AddressInput.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**Address**](Address.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteAddress**
> deleteAddress(xIdempotencyKey, id, xTraceId)

Delete an address

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAddressApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final int id = 789; // int | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    api.deleteAddress(xIdempotencyKey, id, xTraceId);
} catch on DioException (e) {
    print('Exception when calling AddressApi->deleteAddress: $e\n');
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

# **listAddresses**
> ListAddresses200Response listAddresses(xTraceId)

List the authenticated user's delivery addresses

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAddressApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.listAddresses(xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AddressApi->listAddresses: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**ListAddresses200Response**](ListAddresses200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateAddress**
> Address updateAddress(xIdempotencyKey, id, addressInput, xTraceId)

Update an existing address

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getAddressApi();
final String xIdempotencyKey = 01926b7f-1234-7abc-8def-0123456789ab; // String | UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
final int id = 789; // int | 
final AddressInput addressInput = ; // AddressInput | 
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 

try {
    final response = api.updateAddress(xIdempotencyKey, id, addressInput, xTraceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AddressApi->updateAddress: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xIdempotencyKey** | **String**| UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation.  | 
 **id** | **int**|  | 
 **addressInput** | [**AddressInput**](AddressInput.md)|  | 
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 

### Return type

[**Address**](Address.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

