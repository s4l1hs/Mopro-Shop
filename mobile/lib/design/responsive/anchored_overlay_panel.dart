import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable overlay panel anchored to a trigger widget.
///
/// Extracted from the ad-hoc `OverlayPortal` + `CompositedTransformFollower`
/// + shared-hover-state pattern Session 4a built twice (search dropdown +
/// account hover menu). Consumers configure open/close triggers via boolean
/// flags rather than re-implementing the state machine.
///
/// ## Usage
///
/// Anchor a dropdown beneath a search pill, matching its width:
/// ```dart
/// AnchoredOverlayPanel(
///   openOnHover: false,
///   openOnFocus: true,
///   openOnTap: true,
///   matchTriggerWidth: true,
///   trigger: const _SearchPill(),
///   panelBuilder: (ctx, close) => _SuggestionsList(onPick: (_) => close()),
/// )
/// ```
///
/// Anchor a hover menu to the right of an account icon, in an exclusivity
/// group so neighboring panels auto-close each other:
/// ```dart
/// AnchoredOverlayPanel(
///   openDelay: const Duration(milliseconds: 80),
///   closeDelay: const Duration(milliseconds: 150),
///   triggerAnchor: Alignment.bottomRight,
///   panelAnchor: Alignment.topRight,
///   exclusivityGroup: 'header.menus',
///   trigger: const _AvatarChip(),
///   panelBuilder: (context, close) => _AccountMenuPanel(onClose: close),
/// )
/// ```
///
/// ## Behavior contract
///
/// - **Hover** keeps the panel open while the cursor is over EITHER the
///   trigger or the panel itself. Leaving both for `closeDelay` closes.
/// - **Focus** opens after `openDelay` when the trigger (or anything inside
///   it) gains focus; close timing matches hover.
/// - **Tap** toggles open/close (useful for touch-on-web).
/// - **Escape** closes immediately and returns focus to the trigger.
/// - **Outside tap** closes immediately.
/// - **Exclusivity group**: opening any panel in the group closes other panels
///   in the same group — see [exclusivityGroup].
/// - **Viewport resize / scroll**: `CompositedTransformFollower` re-positions
///   the panel automatically.
///
/// ## Known limitations (carried to Session 5)
///
/// - Tab-past-last-focusable inside the panel does NOT yet auto-close the
///   panel and continue normal tab order — current consumers (account menu,
///   search dropdown) don't rely on this. The `Shortcuts`/`Actions` plumbing
///   is in place; wiring `NextFocusAction` requires per-row registration that
///   belongs in a Session 5 a11y sweep.
/// - `closeOnRouteChange` currently relies on the OverlayPortal's natural
///   unmount when the host screen pops. For consumers that navigate via
///   `context.go(...)` BEFORE calling `close`, this is fine. Consumers that
///   need explicit route-change-close should call `close` inside their own
///   route listener.
class AnchoredOverlayPanel extends StatefulWidget {
  const AnchoredOverlayPanel({
    required this.trigger,
    required this.panelBuilder,
    super.key,
    this.triggerAnchor = Alignment.bottomLeft,
    this.panelAnchor = Alignment.topLeft,
    this.offset = const Offset(0, 6),
    this.openDelay = const Duration(milliseconds: 80),
    this.closeDelay = const Duration(milliseconds: 150),
    this.openOnHover = true,
    this.openOnFocus = true,
    this.openOnTap = true,
    this.closeOnOutsideTap = true,
    this.closeOnEscape = true,
    this.closeOnRouteChange = true,
    this.matchTriggerWidth = false,
    this.maxWidth,
    this.exclusivityGroup,
  });

  /// The visible region that controls the panel. Hovering, focusing, or tapping
  /// this opens the panel (subject to the `openOn*` flags).
  final Widget trigger;

  /// Builder for the overlay panel content. The `close` callback hides the
  /// panel and returns focus to the trigger.
  final Widget Function(BuildContext context, VoidCallback close) panelBuilder;

  /// Alignment of the anchor point on the trigger that the panel attaches to.
  final Alignment triggerAnchor;

  /// Alignment of the anchor point on the panel that connects to the trigger.
  final Alignment panelAnchor;

  /// Pixel offset applied on top of the alignment.
  final Offset offset;

  final Duration openDelay;
  final Duration closeDelay;

  final bool openOnHover;
  final bool openOnFocus;
  final bool openOnTap;

  final bool closeOnOutsideTap;
  final bool closeOnEscape;
  final bool closeOnRouteChange;

  /// When true, the panel is clamped to the trigger's measured width.
  final bool matchTriggerWidth;

  /// Hard upper bound on panel width (applied AFTER [matchTriggerWidth]).
  final double? maxWidth;

  /// Opening any panel sharing the same group object instantly closes other
  /// panels in the group. Use the same `Object` instance (typically a unique
  /// string constant) across siblings.
  final Object? exclusivityGroup;

  @override
  State<AnchoredOverlayPanel> createState() => _AnchoredOverlayPanelState();
}

/// Module-level registry tracking the currently-open panel per exclusivity
/// group. Opening a new panel in a group closes the prior one.
final Map<Object, _AnchoredOverlayPanelState> _exclusivityRegistry = {};

class _AnchoredOverlayPanelState extends State<AnchoredOverlayPanel> {
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();
  final _triggerFocusNode =
      FocusNode(debugLabel: 'AnchoredOverlayPanel-trigger');

  bool _hoveringTrigger = false;
  bool _hoveringPanel = false;
  bool _focused = false;
  // True while the panel was opened imperatively by a tap (or by the
  // exclusivity machinery). Pins the panel open until it's explicitly
  // closed by another tap, Escape, outside-tap, or the consumer's `close`
  // callback. Without this, a `_recompute` triggered by hover-leave or
  // focus-leave would close the panel even though the user just tapped to
  // open it.
  bool _pinnedOpen = false;
  Timer? _openTimer;
  Timer? _closeTimer;

  bool get _shouldOpen =>
      _pinnedOpen ||
      (widget.openOnHover && (_hoveringTrigger || _hoveringPanel)) ||
      (widget.openOnFocus && _focused);

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _triggerFocusNode.dispose();
    final group = widget.exclusivityGroup;
    if (group != null && _exclusivityRegistry[group] == this) {
      _exclusivityRegistry.remove(group);
    }
    super.dispose();
  }

  void _open() {
    final group = widget.exclusivityGroup;
    if (group != null) {
      final prior = _exclusivityRegistry[group];
      if (prior != null && prior != this) prior._closeImmediately();
      _exclusivityRegistry[group] = this;
    }
    if (!_overlayController.isShowing) _overlayController.show();
  }

  void _closeImmediately() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _pinnedOpen = false;
    final group = widget.exclusivityGroup;
    if (group != null && _exclusivityRegistry[group] == this) {
      _exclusivityRegistry.remove(group);
    }
    if (_overlayController.isShowing) _overlayController.hide();
  }

  void _dismissAndReturnFocus() {
    _closeImmediately();
    _triggerFocusNode.requestFocus();
  }

  void _recompute() {
    final wantOpen = _shouldOpen;
    final isOpen = _overlayController.isShowing;
    if (wantOpen && !isOpen) {
      _closeTimer?.cancel();
      _openTimer?.cancel();
      if (widget.openDelay == Duration.zero) {
        _open();
      } else {
        _openTimer = Timer(widget.openDelay, () {
          if (mounted && _shouldOpen) _open();
        });
      }
    } else if (!wantOpen && isOpen) {
      _openTimer?.cancel();
      _closeTimer?.cancel();
      if (widget.closeDelay == Duration.zero) {
        _closeImmediately();
      } else {
        _closeTimer = Timer(widget.closeDelay, () {
          if (mounted && !_shouldOpen) _closeImmediately();
        });
      }
    }
  }

  void _handleTap() {
    if (!widget.openOnTap) return;
    if (_overlayController.isShowing) {
      _closeImmediately();
    } else {
      _pinnedOpen = true;
      _open();
      // Move focus into the trigger so the Escape shortcut is in scope.
      _triggerFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      if (widget.closeOnEscape)
        const SingleActivator(LogicalKeyboardKey.escape):
            const _DismissPanelIntent(),
    };

    return CompositedTransformTarget(
      link: _layerLink,
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            _DismissPanelIntent: CallbackAction<_DismissPanelIntent>(
              onInvoke: (_) {
                _dismissAndReturnFocus();
                return null;
              },
            ),
          },
          child: OverlayPortal(
            controller: _overlayController,
            overlayChildBuilder: (overlayContext) {
              return _PanelOverlay(
                layerLink: _layerLink,
                triggerAnchor: widget.triggerAnchor,
                panelAnchor: widget.panelAnchor,
                offset: widget.offset,
                anchorContext: context,
                matchTriggerWidth: widget.matchTriggerWidth,
                maxWidth: widget.maxWidth,
                closeOnOutsideTap: widget.closeOnOutsideTap,
                onDismiss: _dismissAndReturnFocus,
                onPanelEnter: () {
                  _hoveringPanel = true;
                  _recompute();
                },
                onPanelExit: () {
                  _hoveringPanel = false;
                  _recompute();
                },
                child: widget.panelBuilder(
                  overlayContext,
                  _dismissAndReturnFocus,
                ),
              );
            },
            child: MouseRegion(
              onEnter: (_) {
                _hoveringTrigger = true;
                _recompute();
              },
              onExit: (_) {
                _hoveringTrigger = false;
                _recompute();
              },
              child: Focus(
                focusNode: _triggerFocusNode,
                canRequestFocus: true,
                onFocusChange: (f) {
                  _focused = f;
                  _recompute();
                },
                // When openOnTap is true we intercept taps to toggle the
                // panel; when false we deliberately do NOT wrap in a
                // GestureDetector so descendant widgets (e.g. a TextField
                // inside the trigger) keep receiving their own taps.
                child: widget.openOnTap
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _handleTap,
                        child: widget.trigger,
                      )
                    : widget.trigger,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissPanelIntent extends Intent {
  const _DismissPanelIntent();
}

/// Outer overlay shell: full-viewport dismisser + `CompositedTransformFollower`
/// positioning + MouseRegion that keeps the parent's shared hover state in
/// sync when the cursor moves onto the panel.
class _PanelOverlay extends StatelessWidget {
  const _PanelOverlay({
    required this.layerLink,
    required this.triggerAnchor,
    required this.panelAnchor,
    required this.offset,
    required this.anchorContext,
    required this.matchTriggerWidth,
    required this.maxWidth,
    required this.closeOnOutsideTap,
    required this.onDismiss,
    required this.onPanelEnter,
    required this.onPanelExit,
    required this.child,
  });

  final LayerLink layerLink;
  final Alignment triggerAnchor;
  final Alignment panelAnchor;
  final Offset offset;
  final BuildContext anchorContext;
  final bool matchTriggerWidth;
  final double? maxWidth;
  final bool closeOnOutsideTap;
  final VoidCallback onDismiss;
  final VoidCallback onPanelEnter;
  final VoidCallback onPanelExit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final triggerSize =
        (anchorContext.findRenderObject() as RenderBox?)?.size ?? Size.zero;

    double? effectiveWidth;
    if (matchTriggerWidth) {
      effectiveWidth = triggerSize.width;
    }
    if (maxWidth != null) {
      effectiveWidth = effectiveWidth == null
          ? maxWidth
          : (effectiveWidth < maxWidth! ? effectiveWidth : maxWidth);
    }

    // Project the trigger-anchor point into trigger-local coords.
    final triggerAnchorOffset = Offset(
      triggerSize.width * (triggerAnchor.x + 1) / 2,
      triggerSize.height * (triggerAnchor.y + 1) / 2,
    );
    // Project the panel-anchor point into panel-local coords. Only computable
    // when the effective panel width is known (matchTriggerWidth or maxWidth).
    // When unknown, panelAnchor must be Alignment.topLeft — the default — and
    // the projection is the zero vector.
    var panelAnchorOffset = Offset.zero;
    if (effectiveWidth != null) {
      panelAnchorOffset = Offset(
        effectiveWidth * (panelAnchor.x + 1) / 2,
        // Height isn't known at this point (panel can be any height); only x
        // is corrected via panelAnchor. y-anchoring on the panel side would
        // require measuring after layout, which the current consumers don't
        // need (both anchor by the panel's top edge).
        0,
      );
    }

    final followerOffset =
        triggerAnchorOffset - panelAnchorOffset + offset;

    final panel = MouseRegion(
      onEnter: (_) => onPanelEnter(),
      onExit: (_) => onPanelExit(),
      child: effectiveWidth != null
          ? SizedBox(width: effectiveWidth, child: child)
          : child,
    );

    return Stack(
      children: [
        if (closeOnOutsideTap)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onDismiss,
            ),
          ),
        CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          offset: followerOffset,
          child: panel,
        ),
      ],
    );
  }
}

/// Test-only hook: clear the exclusivity registry between tests so leftover
/// state doesn't bleed across cases. Not exported via the public API.
@visibleForTesting
void debugResetAnchoredOverlayPanelRegistry() {
  _exclusivityRegistry.clear();
}
