import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/features/wallet/providers/plan_detail_provider.dart';
import 'package:mopro_api/mopro_api.dart';

// ── Fixtures

CashbackPlan _plan(int id) => CashbackPlan(
      id: id,
      orderId: id * 10,
      productId: 0,
      productTitle: 'Plan $id',
      monthlyAmountMinor: 5000,
      currency: 'TRY_COIN',
      status: CashbackPlanStatusEnum.active,
      startDate: DateTime(2026),
      referenceInterestRateBps: 5000,
      createdAt: DateTime(2026),
    );

CashbackPayment _payment(int id) => CashbackPayment(
      id: id,
      planId: 1,
      periodYyyymm: '202601',
      amountMinor: 5000,
      currency: 'TRY_COIN',
      status: CashbackPaymentStatusEnum.paid,
      paidAt: DateTime(2026),
    );

// ── Fake CashbackApi

class _FakeCashbackApi extends CashbackApi {
  _FakeCashbackApi({
    this.payments = const [],
  }) : super(Dio());

  final List<CashbackPayment> payments;

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
  }) async =>
      Response(
        data: _plan(id),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );

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
  }) async =>
          Response(
            data: ListCashbackPayments200Response(
              data: payments,
              pagination: CursorPaginationMeta(hasMore: false),
            ),
            requestOptions: RequestOptions(),
            statusCode: 200,
          );

  @override
  Future<Response<ListCashbackPlans200Response>> listCashbackPlans({
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
  }) =>
      throw UnimplementedError();
}

// ── Tests

void main() {
  test('initial state is loading', () {
    final container = ProviderContainer(
      overrides: [
        cashbackApiProvider.overrideWithValue(
          _FakeCashbackApi(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final s = container.read(planDetailProvider(1));
    expect(s.plan, isA<AsyncLoading<CashbackPlan>>());
    expect(
      s.payments,
      isA<AsyncLoading<List<CashbackPayment>>>(),
    );
  });

  test('loads plan and payments in parallel', () async {
    final container = ProviderContainer(
      overrides: [
        cashbackApiProvider.overrideWithValue(
          _FakeCashbackApi(
            payments: [_payment(1), _payment(2)],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // listen keeps autoDispose provider alive while async _init runs
    final sub = container.listen(planDetailProvider(1), (_, __) {});
    addTearDown(sub.close);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final s = container.read(planDetailProvider(1));

    expect(s.plan.valueOrNull?.id, 1);
    expect(s.payments.valueOrNull?.length, 2);
  });

  test('separate family instances are independent', () async {
    final container = ProviderContainer(
      overrides: [
        cashbackApiProvider.overrideWithValue(
          _FakeCashbackApi(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final sub1 = container.listen(planDetailProvider(1), (_, __) {});
    final sub2 = container.listen(planDetailProvider(2), (_, __) {});
    addTearDown(sub1.close);
    addTearDown(sub2.close);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final s1 = container.read(planDetailProvider(1));
    final s2 = container.read(planDetailProvider(2));

    expect(s1.plan.valueOrNull?.id, 1);
    expect(s2.plan.valueOrNull?.id, 2);
  });
}
