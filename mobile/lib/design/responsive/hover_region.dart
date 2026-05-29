import 'dart:async';

import 'package:flutter/widgets.dart';

/// MouseRegion wrapper that exposes a `hovering` flag to its child
/// builder with debounced open/close delays. Treats keyboard focus as
/// hovering so the mega-menu and dropdown patterns are keyboard-usable.
class HoverRegion extends StatefulWidget {
  const HoverRegion({
    required this.builder,
    this.openDelay = Duration.zero,
    this.closeDelay = const Duration(milliseconds: 150),
    this.focusNode,
    super.key,
  });

  /// Builder receives `hovering=true` while the pointer is inside the region
  /// (after `openDelay`) or the descendant focus node has focus. Positional
  /// `bool` matches Flutter's idiomatic builder-typedef convention.
  // ignore: avoid_positional_boolean_parameters
  final Widget Function(BuildContext context, bool hovering) builder;
  final Duration openDelay;
  final Duration closeDelay;
  final FocusNode? focusNode;

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _hovering = false;
  bool _focused = false;
  Timer? _openTimer;
  Timer? _closeTimer;
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();

  bool get _active => _hovering || _focused;

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _scheduleOpen() {
    _closeTimer?.cancel();
    if (widget.openDelay == Duration.zero) {
      if (mounted) setState(() {});
      return;
    }
    _openTimer?.cancel();
    _openTimer = Timer(widget.openDelay, () {
      if (mounted) setState(() {});
    });
  }

  void _scheduleClose() {
    _openTimer?.cancel();
    if (widget.closeDelay == Duration.zero) {
      if (mounted) setState(() {});
      return;
    }
    _closeTimer?.cancel();
    _closeTimer = Timer(widget.closeDelay, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _hovering = true;
        _scheduleOpen();
      },
      onExit: (_) {
        _hovering = false;
        _scheduleClose();
      },
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (f) {
          _focused = f;
          f ? _scheduleOpen() : _scheduleClose();
        },
        child: widget.builder(context, _active),
      ),
    );
  }
}
