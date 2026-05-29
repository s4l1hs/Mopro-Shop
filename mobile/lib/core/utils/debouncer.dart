import 'dart:async';
import 'package:flutter/foundation.dart';

/// Coalesces rapid calls: only the last [run] within [delay] fires. Call
/// [dispose] to cancel a pending action (e.g. in `State.dispose`).
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() => _timer?.cancel();
}
