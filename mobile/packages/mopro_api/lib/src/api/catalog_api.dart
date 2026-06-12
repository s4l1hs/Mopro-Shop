//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

// ignore: unused_import
import 'dart:convert';
import 'package:mopro_api/src/deserialize.dart';
import 'package:dio/dio.dart';

import 'package:mopro_api/src/model/category_commission.dart';
import 'package:mopro_api/src/model/create_product_request.dart';
import 'package:mopro_api/src/model/error_envelope.dart';
import 'package:mopro_api/src/model/get_category_facets200_response.dart';
import 'package:mopro_api/src/model/list_categories200_response.dart';
import 'package:mopro_api/src/model/list_products200_response.dart';
import 'package:mopro_api/src/model/product.dart';
import 'package:mopro_api/src/model/size_recommendation.dart';

class CatalogApi {

  final Dio _dio;

  const CatalogApi(this._dio);

  /// Create a new product listing (admin / seller onboarding)
  /// 
  ///
  /// Parameters:
  /// * [xIdempotencyKey] - UUIDv7 generated client-side. Server caches the response for 24 hours keyed on this value. Duplicate requests within that window return the cached response without re-executing the operation. 
  /// * [createProductRequest] 
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [Product] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<Product>> createProduct({ 
    required String xIdempotencyKey,
    required CreateProductRequest createProductRequest,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/products';
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        if (xTraceId != null) r'X-Trace-Id': xTraceId,
        r'X-Idempotency-Key': xIdempotencyKey,
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'adminAuth',
          },
        ],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
_bodyData=jsonEncode(createProductRequest);
    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    Product? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<Product, Product>(rawData, 'Product', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<Product>(
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

  /// Get live commission and KDV rates for a category + market pair
  /// 
  ///
  /// Parameters:
  /// * [id] 
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [market] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [CategoryCommission] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<CategoryCommission>> getCategoryCommission({ 
    required int id,
    String? xTraceId,
    String? market = 'TR',
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/categories/{id}/commission'.replaceAll('{' r'id' '}', id.toString());
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
            'name': 'adminAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{
      if (market != null) r'market': market,
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    CategoryCommission? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<CategoryCommission, CategoryCommission>(rawData, 'CategoryCommission', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<CategoryCommission>(
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

  /// Faceted attribute aggregation for a category (PLP-13)
  /// For each facetable attribute of the category (and its subtree, PLP-12), returns the (value, count) buckets — the buyer-facing filter facets (mirrors the brand/rating facets). Driven by &#x60;category_facets&#x60; + &#x60;product_attributes&#x60;; counts are DISTINCT products. Names are resolved from &#x60;Accept-Language&#x60;. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GetCategoryFacets200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetCategoryFacets200Response>> getCategoryFacets({ 
    required int id,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/categories/{id}/facets'.replaceAll('{' r'id' '}', id.toString());
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

    GetCategoryFacets200Response? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<GetCategoryFacets200Response, GetCategoryFacets200Response>(rawData, 'GetCategoryFacets200Response', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetCategoryFacets200Response>(
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

  /// Get full product detail including variants and cashback preview
  /// Server resolves &#x60;title&#x60; and &#x60;description&#x60; from &#x60;Accept-Language&#x60; header. &#x60;cashback_preview.monthly_coin_minor&#x60; is computed handler-layer: &#x60;round(variant.price_minor × commission_pct_bps/10000 × 5000/10000 / 12)&#x60;. Uses the lowest-priced active variant for the preview amount. &#x60;seller_name&#x60; is joined from the seller module (in-process, core-svc only). &#x60;image_urls&#x60; are CDN-resolved (not raw storage keys). &#x60;delivery_eta&#x60; is a cheap, table-driven pre-purchase delivery estimate (P-034) from the seller&#39;s dispatch origin to the optional &#x60;dest_city&#x60;; it makes NO carrier call. Omitted (null) when no estimate is available. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [destCity] - Destination city for the delivery estimate (P-034). The client passes the user's selected delivery city when known; absent (a guest) yields the conservative national fallback (delivery_eta.confident = false). Case/diacritic-insensitive (folded to an ASCII key server-side). 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [Product] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<Product>> getProduct({ 
    required int id,
    String? xTraceId,
    String? destCity,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/products/{id}'.replaceAll('{' r'id' '}', id.toString());
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
      if (destCity != null) r'dest_city': destCity,
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    Product? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<Product, Product>(rawData, 'Product', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<Product>(
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

  /// Recommend a size for this product from the user&#39;s fit profile
  /// Size-fit phase 1. chart_approximate is ALWAYS true (representative seed charts + title-keyword garment classification — curation follow-up). Graceful statuses instead of errors: no_profile, incomplete_profile, no_chart. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SizeRecommendation] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SizeRecommendation>> getSizeRecommendation({ 
    required int id,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/products/{id}/size-recommendation'.replaceAll('{' r'id' '}', id.toString());
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

    SizeRecommendation? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<SizeRecommendation, SizeRecommendation>(rawData, 'SizeRecommendation', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SizeRecommendation>(
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

  /// List all 42 product categories (locale-resolved names)
  /// Returns a flat list of active categories; each row carries &#x60;parent_id&#x60; for client-side tree reconstruction. Default behavior returns all depths (mobile callers rely on this — do not change).  Optional &#x60;depth&#x60; query param filters to categories whose chain length to a root parent is at most N (root&#x3D;0, direct children&#x3D;1, …). Used by the desktop mega menu (Session 4c §3) to pre-load the bar + subcategory leaves in one call. Hard ceiling: 1000 nodes per response. 
  ///
  /// Parameters:
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [depth] - Filter chain length from root parent. Valid range 1..3. Omitting the param returns all depths (historical behavior). 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListCategories200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListCategories200Response>> listCategories({ 
    String? xTraceId,
    int? depth,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/categories';
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
      if (depth != null) r'depth': depth,
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ListCategories200Response? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<ListCategories200Response, ListCategories200Response>(rawData, 'ListCategories200Response', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListCategories200Response>(
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

  /// List products with category filter, price/brand/rating/shipping filters, pagination, and sort
  /// 
  ///
  /// Parameters:
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
  Future<Response<ListProducts200Response>> listProducts({ 
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
    final _path = r'/products';
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

}
