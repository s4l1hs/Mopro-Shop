# mopro_api.api.WalletApi

## Load the API package
```dart
import 'package:mopro_api/api.dart';
```

All URIs are relative to *https://api.moproshop.com*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getWalletBalance**](WalletApi.md#getwalletbalance) | **GET** /v1/wallet/balance | Get the authenticated user&#39;s coin wallet balance
[**listWalletTransactions**](WalletApi.md#listwallettransactions) | **GET** /v1/wallet/transactions | List wallet transaction history (cursor-paginated)


# **getWalletBalance**
> WalletBalance getWalletBalance(xTraceId, currency)

Get the authenticated user's coin wallet balance

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getWalletApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final String currency = currency_example; // String | 

try {
    final response = api.getWalletBalance(xTraceId, currency);
    print(response);
} catch on DioException (e) {
    print('Exception when calling WalletApi->getWalletBalance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **currency** | **String**|  | [optional] [default to 'TRY_COIN']

### Return type

[**WalletBalance**](WalletBalance.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listWalletTransactions**
> ListWalletTransactions200Response listWalletTransactions(xTraceId, cursor, limit)

List wallet transaction history (cursor-paginated)

### Example
```dart
import 'package:mopro_api/api.dart';

final api = MoproApi().getWalletApi();
final String xTraceId = 4f3a2b1c-e71a-4c3f-b99a-8c3f2a1b7d5e; // String | Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
final String cursor = cursor_example; // String | 
final int limit = 56; // int | 

try {
    final response = api.listWalletTransactions(xTraceId, cursor, limit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling WalletApi->listWalletTransactions: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **xTraceId** | **String**| Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent.  | [optional] 
 **cursor** | **String**|  | [optional] 
 **limit** | **int**|  | [optional] [default to 24]

### Return type

[**ListWalletTransactions200Response**](ListWalletTransactions200Response.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

