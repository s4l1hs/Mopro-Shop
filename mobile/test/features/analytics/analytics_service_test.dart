// ignore_for_file: cascade_invocations — sequential svc.track()/flush() calls
// read more clearly as separate statements in these tests.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/analytics/analytics_service.dart';

class _Sink {
  final List<List<AnalyticsEvent>> batches = [];
  bool fail = false;
  Future<void> call(String sessionId, List<AnalyticsEvent> batch) async {
    if (fail) throw Exception('network');
    batches.add(List.of(batch));
  }
}

AnalyticsService _svc(
  _Sink sink, {
  bool gate = true,
  int batchSize = 20,
  Duration interval = const Duration(milliseconds: 20),
}) =>
    AnalyticsService(
      sessionId: 'sess-1',
      gate: () => gate,
      sink: sink.call,
      batchSize: batchSize,
      flushInterval: interval,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gate false drops events', () async {
    final sink = _Sink();
    final svc = _svc(sink, gate: false);
    svc.track(AnalyticsEvent('page_view', {'path': '/'}));
    await svc.flush();
    expect(sink.batches, isEmpty);
    svc.dispose();
  });

  test('first track prepends session_start', () async {
    final sink = _Sink();
    final svc = _svc(sink);
    svc.track(AnalyticsEvent('product_view', {'productId': 1}));
    await svc.flush();
    expect(sink.batches.single.first.type, 'session_start');
    expect(sink.batches.single[1].type, 'product_view');
    svc.dispose();
  });

  test('batch size threshold flushes', () async {
    final sink = _Sink();
    final svc = _svc(sink, batchSize: 3);
    // 3 events + the auto session_start = exceeds 3 → flush.
    svc.track(AnalyticsEvent('page_view', {'path': '/a'}));
    svc.track(AnalyticsEvent('page_view', {'path': '/b'}));
    svc.track(AnalyticsEvent('page_view', {'path': '/c'}));
    await Future<void>.delayed(Duration.zero);
    expect(sink.batches, isNotEmpty);
    svc.dispose();
  });

  test('timer interval flushes', () async {
    final sink = _Sink();
    final svc = _svc(sink, interval: const Duration(milliseconds: 10));
    svc.track(AnalyticsEvent('page_view', {'path': '/'}));
    expect(sink.batches, isEmpty); // below batch size, not yet flushed
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(sink.batches, isNotEmpty); // timer fired
    svc.dispose();
  });

  test('retry retains queue on failure then drops after 3', () async {
    final sink = _Sink()..fail = true;
    final svc = _svc(sink);
    svc.track(AnalyticsEvent('page_view', {'path': '/'}));
    await svc.flush(); // failure 1 — retained
    await svc.flush(); // failure 2 — retained
    expect(sink.batches, isEmpty);
    await svc.flush(); // failure 3 — dropped
    sink.fail = false;
    await svc.flush(); // queue empty now
    expect(sink.batches, isEmpty);
    svc.dispose();
  });

  test('session_end emitted on app pause', () async {
    final sink = _Sink();
    final svc = _svc(sink);
    svc.track(AnalyticsEvent('product_view', {'productId': 1}));
    svc.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    final types = sink.batches.expand((b) => b).map((e) => e.type).toList();
    expect(types, contains('session_end'));
    svc.dispose();
  });
}
