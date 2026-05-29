import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
/// The "kind" of the most recent pointer interaction. Lets widgets adjust
/// behavior between mouse/trackpad/stylus (pointer) and finger (touch) on
/// the same physical device — relevant for hybrid Web/desktop hardware
/// (e.g. a touchscreen laptop, an iPad with a trackpad).
///
/// `mouse` is the default until a pointer event fires; `unknown` is only
/// emitted before the observer is installed. `trackpad` is folded into
/// `mouse` (precise indirect input behaves the same as a mouse from the
/// UX side).
enum LastPointerKind { unknown, mouse, touch, stylus }
/// Global observer that tracks the kind of the most recent `PointerDownEvent`
/// and exposes it via a `ValueNotifier`. Install once in `main.dart` after
/// `WidgetsFlutterBinding.ensureInitialized()`.
///
/// Consumers wrap their UI in `ValueListenableBuilder<LastPointerKind>(
/// valueListenable: PointerKindObserver.lastKind, builder: ...)` to rebuild
/// when the kind changes.
///
/// Why a global notifier instead of a Riverpod provider: this is platform
/// state, not application state. Wrapping it in Riverpod would add layers
/// without changing semantics. The `ValueNotifier` is also test-friendly
/// — tests can write directly to `.value` to simulate pointer kinds without
/// needing to synthesize real `PointerDownEvent`s.
class PointerKindObserver {
  PointerKindObserver._();
  static final ValueNotifier<LastPointerKind> lastKind =
      ValueNotifier<LastPointerKind>(LastPointerKind.unknown);
  static bool _installed = false;
  /// Attach the global pointer-router hook. Idempotent: calling twice
  /// only installs the handler once.
  static void install() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }
  /// Test hook: tear down + reset to unknown. Production code never calls
  /// this; tests use it in `tearDown` so observer state doesn't leak
  /// across cases.
  @visibleForTesting
  static void debugReset() {
    if (_installed) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      _installed = false;
    }
    lastKind.value = LastPointerKind.unknown;
  }
  static void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    final mapped = _map(event.kind);
    if (lastKind.value != mapped) {
      lastKind.value = mapped;
    }
  }
  static LastPointerKind _map(PointerDeviceKind kind) {
    switch (kind) {
      case PointerDeviceKind.touch:
        return LastPointerKind.touch;
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        return LastPointerKind.stylus;
      case PointerDeviceKind.mouse:
      case PointerDeviceKind.trackpad:
        return LastPointerKind.mouse;
      case PointerDeviceKind.unknown:
        return LastPointerKind.unknown;
    }
  }
}
