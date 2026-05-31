import 'package:flutter/material.dart';
import 'package:mopro/design/responsive/breakpoints.dart';
import 'package:mopro/design/responsive/centered_content_column.dart';
import 'package:mopro/design/responsive/responsive_builder.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/account/widgets/account_left_rail.dart';
import 'package:mopro/features/account/widgets/account_right_pane.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_bar.dart';
import 'package:mopro/shell/web_header.dart';

/// Wraps the account-section routes (`/account/*`, `/orders`, `/wallet`,
/// `/profile/addresses`) in the desktop/tablet two-pane layout. Mounted as a
/// top-level `ShellRoute` builder.
///
/// - Mobile (`<600`): pure pass-through. The child renders full-screen with its
///   own app bar exactly as before the shell existed — mobile list-then-detail
///   is untouched.
/// - Tablet/desktop: `WebHeader` (+ `MegaMenuBar` ≥768, matching `AppShell`) over
///   a two-pane body — a sticky `AccountLeftRail` on the left and the matched
///   child (with its own app bar suppressed by the route builder) on the right.
class AccountShell extends StatelessWidget {
  const AccountShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      mobile: (_) => child,
      tablet: (_) => _TwoPane(child: child),
      desktop: (_) => _TwoPane(child: child),
    );
  }
}

class _TwoPane extends StatelessWidget {
  const _TwoPane({required this.child});

  final Widget child;

  static const double _megaMenuMinWidth = 768;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= Breakpoints.tabletMax;
    final railWidth = isDesktop ? 260.0 : 240.0;
    final gap = isDesktop ? 32.0 : 24.0;
    final showMegaMenu = width >= _megaMenuMinWidth;

    return Scaffold(
      appBar: const WebHeader(),
      body: Column(
        children: [
          if (showMegaMenu) const MegaMenuBar(),
          Expanded(
            child: CenteredContentColumn(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sticky rail: scrolls independently if it ever exceeds height.
                  SizedBox(
                    width: railWidth,
                    child: const SingleChildScrollView(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: AccountLeftRail(),
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: AccountRightPane(
                      child: AccountChromeScope(
                        suppressAppBar: true,
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
