import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for CashbackApi
void main() {
  final instance = MoproApi().getCashbackApi();

  group(CashbackApi, () {
    // Get a single cashback plan
    //
    //Future<CashbackPlan> getCashbackPlan(int id, { String xTraceId }) async
    test('test getCashbackPlan', () async {
      // TODO
    });

    // List monthly payment history for a cashback plan (cursor-paginated)
    //
    //Future<ListCashbackPayments200Response> listCashbackPayments(int id, { String xTraceId, String cursor, int limit }) async
    test('test listCashbackPayments', () async {
      // TODO
    });

    // List the authenticated user's perpetual cashback plans
    //
    //Future<ListCashbackPlans200Response> listCashbackPlans({ String xTraceId, String status, String cursor, int limit }) async
    test('test listCashbackPlans', () async {
      // TODO
    });

  });
}
