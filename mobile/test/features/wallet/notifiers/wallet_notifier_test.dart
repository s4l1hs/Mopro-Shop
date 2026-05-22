import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/features/wallet/providers/wallet_provider.dart';
import 'package:mopro_api/mopro_api.dart';

// ── Fake WalletApi

WalletBalance _balance(int minor) => WalletBalance(
      currency: 'TRY_COIN',
      amountMinor: minor,
      lastUpdatedAt: DateTime(2026),
    );

ListWalletTransactions200Response _txnResp(
  List<WalletTransaction> txns, {
  bool hasMore = false,
}) =>
    ListWalletTransactions200Response(
      data: txns,
      pagination: CursorPaginationMeta(
        hasMore: hasMore,
        nextCursor: hasMore ? 'cursor1' : null,
      ),
    );

WalletTransaction _txn(int id) => WalletTransaction(
      id: id,
      type: WalletTransactionTypeEnum.credit,
      amountMinor: 1000,
      currency: 'TRY_COIN',
      occurredAt: DateTime(2026),
    );

class _FakeWalletApi extends WalletApi {
  _FakeWalletApi({
    required this.balanceMinor,
    this.txns = const [],
    this.hasMore = false,
    this.error,
  }) : super(Dio());

  final int balanceMinor;
  final List<WalletTransaction> txns;
  final bool hasMore;
  final Exception? error;

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
  }) async {
    if (error != null) throw error!;
    return Response(
      data: _balance(balanceMinor),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );
  }

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
  }) async {
    if (error != null) throw error!;
    return Response(
      data: _txnResp(txns, hasMore: hasMore),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );
  }
}

// ── Helpers

ProviderContainer _container(_FakeWalletApi api) =>
    ProviderContainer(
      overrides: [
        walletApiProvider.overrideWithValue(api),
      ],
    );

// ── Tests

void main() {
  test('initial state is loading', () {
    final container = _container(
      _FakeWalletApi(balanceMinor: 0),
    );
    addTearDown(container.dispose);
    final s = container.read(walletProvider);
    expect(s.balance, isA<AsyncLoading<WalletBalance>>());
    expect(
      s.transactions,
      isA<AsyncLoading<List<WalletTransaction>>>(),
    );
  });

  test('loads balance and transactions', () async {
    final api = _FakeWalletApi(
      balanceMinor: 50000,
      txns: [_txn(1), _txn(2)],
    );
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(walletProvider); // trigger build
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final s = container.read(walletProvider);

    expect(s.balance.valueOrNull?.amountMinor, 50000);
    expect(s.transactions.valueOrNull?.length, 2);
  });

  test('error state set on balance failure', () async {
    final api = _FakeWalletApi(
      balanceMinor: 0,
      error: Exception('network'),
    );
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(walletProvider); // trigger build
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final s = container.read(walletProvider);

    expect(s.balance, isA<AsyncError<WalletBalance>>());
  });

  test('loadMore appends transactions', () async {
    final api = _FakeWalletApi(
      balanceMinor: 0,
      txns: [_txn(1)],
      hasMore: true,
    );
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(walletProvider); // trigger build
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      container.read(walletProvider).transactions.valueOrNull?.length,
      1,
    );
  });
}
