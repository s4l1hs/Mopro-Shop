import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mopro/design/tokens.dart';

/// Keyboard-only "skip to main content" affordance. Mounted as the
/// highest-priority focus target in the desktop/tablet shell so the first Tab
/// from the browser chrome lands here. It occupies no visible space until
/// focused (translated off-screen rather than `Visibility(visible:false)`, which
/// would drop it from the traversal order); on focus it slides into the
/// top-left as a brand-orange chip. Enter / Space invoke [onSkip], which moves
/// focus to the route's main content.
class SkipToContentLink extends StatefulWidget {
  const SkipToContentLink({required this.onSkip, super.key});

  final VoidCallback onSkip;

  @override
  State<SkipToContentLink> createState() => _SkipToContentLinkState();
}

class _SkipToContentLinkState extends State<SkipToContentLink> {
  final FocusNode _node = FocusNode(debugLabel: 'skip-to-content');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_node.hasFocus != _focused) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _node
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      widget.onSkip();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: MoproTokens.primaryLight,
      borderRadius: BorderRadius.circular(4),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: widget.onSkip,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'a11y.skip_to_content'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    return FocusTraversalOrder(
      order: const NumericFocusOrder(0),
      child: Focus(
        focusNode: _node,
        onKeyEvent: _onKey,
        child: Transform.translate(
          // Off-screen until focused — keeps the slot in traversal order.
          offset: _focused ? Offset.zero : const Offset(-10000, 0),
          child: Semantics(
            label: 'a11y.skip_to_content'.tr(),
            button: true,
            child: chip,
          ),
        ),
      ),
    );
  }
}
