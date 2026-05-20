//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

// ignore: unused_import
import 'dart:convert';
import 'package:mopro_api/src/deserialize.dart';
import 'package:dio/dio.dart';

import 'package:mopro_api/src/model/error_envelope.dart';
import 'package:mopro_api/src/model/seller_order_breakdown.dart';

class SellerApi {

  final Dio _dio;

  const SellerApi(this._dio);

  /// Seller transparency breakdown for a specific order
  /// Returns per-item commission, KDV, service fee (always 0 for Mopro), and net payout amounts. Used by the seller panel web app.  **Current auth:** Requires &#x60;X-Mopro-Seller-Id&#x60; header containing the seller&#39;s integer ID. Phase 4.2a replaces this with seller JWT (&#x60;bearerAuth&#x60;). 
  ///
  /// Parameters:
  /// * [id] 
  /// * [xMoproSellerId] - Seller ID header. Replaced by JWT in Phase 4.2a.
  /// * [xTraceId] - Client-generated trace identifier (UUID or opaque string). Echoed in error responses as `error.trace_id`. Falls back to a server-generated UUID if absent. 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SellerOrderBreakdown] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SellerOrderBreakdown>> getSellerOrderBreakdown({ 
    required int id,
    @Deprecated('xMoproSellerId is deprecated') required String xMoproSellerId,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/v1/seller/orders/{id}/breakdown'.replaceAll('{' r'id' '}', id.toString());
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        if (xTraceId != null) r'X-Trace-Id': xTraceId,
        r'X-Mopro-Seller-Id': xMoproSellerId,
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

    SellerOrderBreakdown? _responseData;

    try {
final rawData = _response.data;
_responseData = rawData == null ? null : deserialize<SellerOrderBreakdown, SellerOrderBreakdown>(rawData, 'SellerOrderBreakdown', growable: true);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SellerOrderBreakdown>(
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
