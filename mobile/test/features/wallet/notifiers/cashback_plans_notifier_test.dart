import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/features/wallet/providers/cashback_plans_provider.dart';
import 'package:mopro_api/mopro_api.dart';

// ── Fake CashbackApi

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

ListCashbackPlans200Response _plansResp(
  List<CashbackPlan> plans, {
  bool hasMore = false,
}) =>
    ListCashbackPlans200Response(
      data: plans,
      pagination: CursorPaginationMeta(
        hasMore: hasMore,
        nextCursor: hasMore ? 'cursor1' : null,
      ),
    );

class _FakeCashbackApi extends CashbackApi {
  _FakeCashbackApi({this.plans = const []}) : super(Dio());

  final List<CashbackPlan> plans;

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
  }) async =>
      Response(
        data: _plansResp(plans),
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
    final s = container.read(cashbackPlansProvider);
    expect(s.plans, isA<AsyncLoading<List<CashbackPlan>>>());
  });

  test('loads plans list', () async {
    final container = ProviderContainer(
      overrides: [
        cashbackApiProvider.overrideWithValue(
          _FakeCashbackApi(plans: [_plan(1), _plan(2)]),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(cashbackPlansProvider); // trigger build
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final s = container.read(cashbackPlansProvider);
    expect(s.plans.valueOrNull?.length, 2);
  });

  test('empty list is data not loading', () async {
    final container = ProviderContainer(
      overrides: [
        cashbackApiProvider.overrideWithValue(
          _FakeCashbackApi(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(cashbackPlansProvider); // trigger build
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final s = container.read(cashbackPlansProvider);
    expect(s.plans.valueOrNull, isEmpty);
  });
}
