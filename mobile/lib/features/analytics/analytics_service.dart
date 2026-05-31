import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/feature_flags.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:uuid/uuid.dart';

/// A single analytics event awaiting batch flush (Decision 1 taxonomy).
class AnalyticsEvent {
  AnalyticsEvent(this.type, [Map<String, dynamic>? payload])
      : payload = payload ?? const {},
        clientTs = DateTime.now().toUtc();

  final String type;
  final Map<String, dynamic> payload;
  final DateTime clientTs;
}

const _sharedPrefsSessionKey = 'mopro_analytics_session_id';

/// Hybrid-instrumentation client (TRANCHE_4_DESIGN.md §7). Auto events
/// (page_view, session_*) arrive from observers; business events from manual
/// `track()` call sites. All emission funnels through the single consent gate
/// here and a batched `POST /analytics/events` (Decision 6).
class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService({
    required this.sessionId,
    required bool Function() gate,
    required Future<void> Function(String sessionId, List<AnalyticsEvent> batch) sink,
    Future<void> Function(String sessionId)? identifySink,
    this.batchSize = 20,
    this.flushInterval = const Duration(seconds: 5),
    this.maxQueue = 200,
  })  : _gate = gate,
        _sink = sink,
        _identifySink = identifySink {
    // Guarded: a plain (non-widget) test has no initialized binding. Lifecycle
    // flush is a best-effort nicety, never a hard dependency.
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      _observing = false;
    }
  }

  final String sessionId;
  final bool Function() _gate;
  final Future<void> Function(String, List<AnalyticsEvent>) _sink;
  final Future<void> Function(String)? _identifySink;
  final int batchSize;
  final Duration flushInterval;
  final int maxQueue;

  final List<AnalyticsEvent> _queue = [];
  Timer? _timer;
  bool _sessionStarted = false;
  bool _observing = false;
  int _consecutiveFailures = 0;

  /// Enqueues an event if all consent gates pass (build flag, auth, consent).
  /// Denial is silent and happens here so the queue never holds events that
  /// shouldn't be sent.
  void track(AnalyticsEvent event) {
    if (!_gate()) return;
    if (!_sessionStarted) {
      _sessionStarted = true;
      _enqueue(AnalyticsEvent('session_start', {'sessionId': sessionId}));
    }
    _enqueue(event);
  }

  void _enqueue(AnalyticsEvent e) {
    _queue.add(e);
    if (_queue.length > maxQueue) {
      _queue.removeAt(0); // drop oldest under sustained backpressure
    }
    if (_queue.length >= batchSize) {
      unawaited(flush());
    } else {
      _arm();
    }
  }

  void _arm() {
    _timer ??= Timer(flushInterval, () => unawaited(flush()));
  }

  /// Sends the pending batch. On failure the queue is retained and retried on
  /// the next flush; after 3 consecutive failures the batch is dropped so a
  /// flaky network never blocks the app.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;
    final batch = List<AnalyticsEvent>.from(_queue);
    try {
      await _sink(sessionId, batch);
      _queue.removeRange(0, batch.length);
      _consecutiveFailures = 0;
    } catch (_) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3) {
        _queue.removeRange(0, batch.length);
        _consecutiveFailures = 0;
      } else {
        _arm(); // retry on the next interval
      }
    }
  }

  /// Links the persisted guest session to the now-authed user (merge-on-auth,
  /// Decision 4) so the backend backfills the user's recently-viewed projection
  /// from pre-login `product_view` events. Best-effort: never throws into login.
  Future<void> identify() async {
    final sink = _identifySink;
    if (sink == null) return;
    await sink(sessionId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_sessionStarted) {
        _enqueue(AnalyticsEvent('session_end', {'sessionId': sessionId}));
      }
      unawaited(flush());
    }
  }

  void dispose() {
    _timer?.cancel();
    if (_observing) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {/* binding gone */}
    }
  }
}

/// Persistent analytics session id (UUID v4), regenerated on logout so the next
/// session is fresh; merge-on-auth handles continuity for authed users.
String _readOrCreateSessionId(Ref ref) {
  // Resilient: analytics must never break a business flow (e.g. the cart's
  // add_to_cart track site reads this provider). If SharedPreferences isn't
  // wired (some tests), fall back to an ephemeral in-memory session id.
  try {
    final prefs = ref.read(sharedPreferencesProvider);
    final existing = prefs.getString(_sharedPrefsSessionKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    prefs.setString(_sharedPrefsSessionKey, id);
    return id;
  } catch (_) {
    return const Uuid().v4();
  }
}

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final dio = ref.read(dioProvider);
  final sessionId = _readOrCreateSessionId(ref);

  bool gate() {
    if (!kAnalyticsConsentEnabled) return false;
    final authed =
        ref.read(authNotifierProvider).valueOrNull is AuthAuthenticated;
    if (!authed) return false; // Option A: no guest tracking (design §4.4).
    return ref.read(userConsentProvider).analyticsEnabled;
  }

  Future<void> sink(String sid, List<AnalyticsEvent> batch) async {
    await dio.post<void>(
      '/analytics/events',
      data: <String, dynamic>{
        'sessionId': sid,
        'events': [
          for (final e in batch)
            {
              'type': e.type,
              'payload': e.payload,
              'clientTs': e.clientTs.toIso8601String(),
            },
        ],
      },
    );
  }

  Future<void> identifySink(String sid) async {
    await dio.post<void>(
      '/analytics/sessions/identify',
      data: <String, dynamic>{'sessionId': sid},
    );
  }

  final svc = AnalyticsService(
    sessionId: sessionId,
    gate: gate,
    sink: sink,
    identifySink: identifySink,
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// go_router observer that auto-emits `page_view` on navigation (the only auto
/// business-agnostic event; everything else is manual per design §7).
class AnalyticsNavObserver extends NavigatorObserver {
  AnalyticsNavObserver(this._service);
  final AnalyticsService Function() _service;

  void _emit(Route<dynamic>? route, Route<dynamic>? previous) {
    final path = route?.settings.name;
    if (path == null) return;
    final from = previous?.settings.name;
    _service().track(
      AnalyticsEvent('page_view', {
        'path': path,
        if (from != null) 'fromPath': from,
      }),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _emit(route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _emit(newRoute, oldRoute);
}
