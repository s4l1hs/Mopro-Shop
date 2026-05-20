import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

const _mutatingMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};
const _header = 'X-Idempotency-Key';

class IdempotencyInterceptor extends Interceptor {
  IdempotencyInterceptor({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_mutatingMethods.contains(options.method.toUpperCase()) &&
        !options.headers.containsKey(_header)) {
      options.headers[_header] = _uuid.v4();
    }
    handler.next(options);
  }
}
