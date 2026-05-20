import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class TraceInterceptor extends Interceptor {
  TraceInterceptor({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Trace-Id'] = _uuid.v4();
    handler.next(options);
  }
}
