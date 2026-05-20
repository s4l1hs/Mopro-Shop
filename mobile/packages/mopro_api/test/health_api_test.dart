import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for HealthApi
void main() {
  final instance = MoproApi().getHealthApi();

  group(HealthApi, () {
    // Health check (liveness probe)
    //
    //Future<String> healthz({ String xTraceId }) async
    test('test healthz', () async {
      // TODO
    });

  });
}
