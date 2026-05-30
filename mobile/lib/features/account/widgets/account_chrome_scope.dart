import 'package:flutter/widgets.dart';

/// Signals to account-section screens that they are being rendered inside the
/// desktop/tablet `AccountShell` two-pane and should suppress their own top
/// chrome (app bar / back button) — the left rail handles navigation.
///
/// Chrome-suppression strategy (Approach B from the prompt): the shell provides
/// this scope once around the child; each screen reads it in one line
/// (`AccountChromeScope.suppressed(context)`) rather than each screen gaining a
/// constructor arg threaded through every route builder. On mobile the shell is
/// a pass-through and never inserts the scope, so screens render their app bar.
class AccountChromeScope extends InheritedWidget {
  const AccountChromeScope({
    required this.suppressAppBar,
    required super.child,
    super.key,
  });

  final bool suppressAppBar;

  /// True when the calling screen is inside the shell on desktop/tablet and
  /// should hide its own app bar. False everywhere else (mobile, standalone).
  static bool suppressed(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AccountChromeScope>();
    return scope?.suppressAppBar ?? false;
  }

  @override
  bool updateShouldNotify(AccountChromeScope oldWidget) =>
      oldWidget.suppressAppBar != suppressAppBar;
}
