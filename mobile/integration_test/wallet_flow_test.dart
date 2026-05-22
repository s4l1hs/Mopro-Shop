import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/router/app_router.dart';
import 'package:mopro/core/theme/app_theme.dart';
import 'package:mopro_api/mopro_api.dart';

// ── Minimal stubs

class _StubWalletApi extends WalletApi {
  _StubWalletApi() : super(Dio());

  @override
  Future<Response<WalletBalance>> getWalletBalance({
    String? xTraceId,
    String? currency = 'TRY_COIN',
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response(
        data: WalletBalance(
          currency: 'TRY_COIN',
          amountMinor: 50000,
          lastUpdatedAt: DateTime(2026),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );

  @override
  Future<Response<ListWalletTransactions200Response>>
      listWalletTransactions({
    String? xTraceId,
    String? cursor,
    int? limit = 24,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
          Response(
            data: ListWalletTransactions200Response(
              data: const [],
              pagination: CursorPaginationMeta(hasMore: false),
            ),
            requestOptions: RequestOptions(),
            statusCode: 200,
          );
}

class _StubCashbackApi extends CashbackApi {
  _StubCashbackApi() : super(Dio());

  @override
  Future<Response<ListCashbackPlans200Response>>
      listCashbackPlans({
    String? xTraceId,
    String? status,
    String? cursor,
    int? limit = 20,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
          Response(
            data: ListCashbackPlans200Response(
              data: const [],
              pagination: CursorPaginationMeta(hasMore: false),
            ),
            requestOptions: RequestOptions(),
            statusCode: 200,
          );

  @override
  Future<Response<CashbackPlan>> getCashbackPlan({
    required int id,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) =>
      throw UnimplementedError();

  @override
  Future<Response<ListCashbackPayments200Response>>
      listCashbackPayments({
    required int id,
    String? xTraceId,
    String? cursor,
    int? limit = 24,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) =>
          throw UnimplementedError();
}

// ── App under test

Widget _app() => ProviderScope(
      overrides: [
        walletApiProvider.overrideWithValue(_StubWalletApi()),
        cashbackApiProvider.overrideWithValue(_StubCashbackApi()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final router = ref.watch(routerProvider);
          return MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          );
        },
      ),
    );

// ── Tests

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('wallet screens render without exceptions',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
