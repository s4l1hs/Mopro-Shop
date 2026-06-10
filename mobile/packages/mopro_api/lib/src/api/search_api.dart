//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

// ignore: unused_import
import 'dart:convert';
import 'package:mopro_api/src/deserialize.dart';
import 'package:dio/dio.dart';

import 'package:mopro_api/src/model/error_envelope.dart';
import 'package:mopro_api/src/model/list_products200_response.dart';
import 'package:mopro_api/src/model/search_trending200_response.dart';
import 'package:mopro_api/src/model/suggest_response.dart';

class SearchApi {

  final Dio _dio;

  const SearchApi(this._dio);

  /// Full-text product search with filters
  /// 
  ///
  /// Parameters:
  /// * [q] 
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [categoryId] - Scope results to a category (optional on /search).
  /// * [page] 
  /// * [perPage] 
  /// * [minPrice] - Minimum price in minor units (filters the displayed/lowest variant price).
  /// * [maxPrice] - Maximum price in minor units (filters the displayed/lowest variant price).
  /// * [brand] - Repeatable; matches any of the given brands (?brand=Nike&brand=Adidas).
  /// * [rating] - Minimum average rating (products with rating_avg >= this).
  /// * [freeShipping] - When true, only products flagged free-shipping.
  /// * [inStock] - When true, only products with at least one in-stock variant.
  /// * [priceDropped] - When true, only products whose current (cheapest live) price is below a price they carried earlier in the last 30 days — a genuine price drop (PLP-14, \"Fiyatı düşenler\"). Served from catalog_schema.variant_price_history. 
  /// * [attr] - Attribute facet filter (PLP-13). Repeated `<slug>:<value>` entries, e.g. `attr=renk:Siyah&attr=renk:Beyaz`. Values within a slug are OR; distinct slugs are AND. Backed by catalog_schema.product_attributes. 
  /// * [sort] - Sort order. Unknown/unsupported tokens fall back to `recommended`. `bestseller` orders by global popularity (P-029); it degrades to `recommended` until the analytics popularity projection has data. 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListProducts200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListProducts200Response>> search({ 
    required String q,
    String? xTraceId,
    int? categoryId,
    int? page = 1,
    int? perPage = 20,
    int? minPrice,
    int? maxPrice,
    List<String>? brand,
    int? rating,
    bool? freeShipping,
    bool? inStock,
    bool? priceDropped,
    List<String>? attr,
    String? sort = 'recommended',
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/search';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        if (xTraceId != null) r'X-Trace-Id': xTraceId,
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{
      r'q': q,
      if (categoryId != null) r'category_id': categoryId,
      if (page != null) r'page': page,
      if (perPage != null) r'per_page': perPage,
      if (minPrice != null) r'min_price': minPrice,
      if (maxPrice != null) r'max_price': maxPrice,
      if (brand != null) r'brand': brand,
      if (rating != null) r'rating': rating,
      if (freeShipping != null) r'free_shipping': freeShipping,
      if (inStock != null) r'in_stock': inStock,
      if (priceDropped != null) r'price_dropped': priceDropped,
      if (attr != null) r'attr': attr,
      if (sort != null) r'sort': sort,
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ListProducts200Response? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<ListProducts200Response, ListProducts200Response>(rawData, 'ListProducts200Response', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListProducts200Response>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// Structured autocomplete suggestions (debounce 300 ms on client)
  /// Returns structured brand + product suggestions for the search dropdown (SE-06). Brands route to the brand-filtered listing; products route to the PDP. Both are sourced from the catalog alone. 
  ///
  /// Parameters:
  /// * [q] 
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SuggestResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SuggestResponse>> searchSuggest({ 
    required String q,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/search/suggest';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        if (xTraceId != null) r'X-Trace-Id': xTraceId,
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{
      r'q': q,
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    SuggestResponse? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<SuggestResponse, SuggestResponse>(rawData, 'SuggestResponse', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SuggestResponse>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// Current trending search terms
  /// 
  ///
  /// Parameters:
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SearchTrending200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SearchTrending200Response>> searchTrending({ 
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/search/trending';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        if (xTraceId != null) r'X-Trace-Id': xTraceId,
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    SearchTrending200Response? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<SearchTrending200Response, SearchTrending200Response>(rawData, 'SearchTrending200Response', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SearchTrending200Response>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

}
