import 'package:flutter/material.dart';

/// The right pane of the account two-pane layout. In the Option-A architecture
/// the bare `/account` welcome panel is rendered by `AccountScreen` itself (it
/// stays the bottom-nav tab), so the shell's right pane simply hosts the matched
/// child route's (chrome-suppressed) screen content.
class AccountRightPane extends StatelessWidget {
  const AccountRightPane({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
