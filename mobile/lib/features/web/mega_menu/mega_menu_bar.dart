import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/anchored_overlay_panel.dart';
import 'package:mopro/design/responsive/pointer_kind.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_focus_ring.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_panel.dart';

/// Persistent top-level category bar mounted directly under the `WebHeader`
/// at `>=768` widths. Below 768dp the bar is NOT in the widget tree.
///
/// Each bar item wraps in an `AnchoredOverlayPanel` (`exclusivityGroup:
/// "megamenu"`) that opens on hover/focus. Tap behavior depends on the last
/// observed pointer kind (Session 4d): pointer routes to the PLP; touch opens
/// the panel.
///
/// ## Keyboard contract (Session 4e §4.2)
///
/// - **Tab / Shift+Tab** move between bar items in source order.
/// - **Arrow Right / Left** move the active bar item; focusing it opens its
///   panel (exclusivity closes the prior one).
/// - **Arrow Down** opens the focused item's panel and moves focus to the first
///   leaf of the first column.
/// - **Enter / Space** invoke label behavior: route to the PLP on pointer-class
///   devices, open the panel on touch-class devices.
/// - **Escape** closes any open panel; focus stays on the bar item
///   (handled by `AnchoredOverlayPanel`).
///
/// A keyboard-only focus ring (`MegaMenuFocusRing`) wraps each item's
/// label+chevron region.
class MegaMenuBar extends ConsumerWidget {
  const MegaMenuBar({super.key});

  static const double height = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final asyncTree = ref.watch(categoryTreeProvider);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: CenteredContentColumn(
        child: asyncTree.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (roots) {
            if (roots.isEmpty) return const SizedBox.shrink();
            return _BarScroller(roots: roots);
          },
        ),
      ),
    );
  }
}

/// Horizontal scroller with edge fade masks. Owns one [FocusNode] per bar item
/// so Arrow Left/Right can move focus between siblings deterministically.
class _BarScroller extends StatefulWidget {
  const _BarScroller({required this.roots});
  final List<CategoryNode> roots;

  @override
  State<_BarScroller> createState() => _BarScrollerState();
}

class _BarScrollerState extends State<_BarScroller> {
  final _scrollController = ScrollController();
  late List<FocusNode> _itemFocusNodes;

  @override
  void initState() {
    super.initState();
    _itemFocusNodes = _makeNodes(widget.roots.length);
  }

  @override
  void didUpdateWidget(_BarScroller old) {
    super.didUpdateWidget(old);
    if (old.roots.length != widget.roots.length) {
      for (final n in _itemFocusNodes) {
        n.dispose();
      }
      _itemFocusNodes = _makeNodes(widget.roots.length);
    }
  }

  List<FocusNode> _makeNodes(int n) => List.generate(
        n,
        (i) => FocusNode(debugLabel: 'megamenu-bar-item-$i'),
      );

  @override
  void dispose() {
    _scrollController.dispose();
    for (final n in _itemFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  /// Move focus to the sibling at [from] + [delta], clamped to the ends.
  void _focusSibling(int from, int delta) {
    final next = (from + delta).clamp(0, _itemFocusNodes.length - 1);
    if (next != from) _itemFocusNodes[next].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Top-level categories',
      child: ShaderMask(
        shaderCallback: (rect) {
          return const LinearGradient(
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.025, 0.975, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: widget.roots.length,
          separatorBuilder: (_, __) => const SizedBox(width: 4),
          itemBuilder: (context, i) {
            return _BarItem(
              node: widget.roots[i],
              isActive: _isActiveRoute(context, widget.roots[i]),
              focusNode: _itemFocusNodes[i],
              onFocusSibling: (delta) => _focusSibling(i, delta),
            );
          },
        ),
      ),
    );
  }

  bool _isActiveRoute(BuildContext context, CategoryNode node) {
    final loc = GoRouterState.of(context).uri.toString();
    return loc.startsWith('/categories/${node.id}');
  }
}

class _BarItem extends StatefulWidget {
  const _BarItem({
    required this.node,
    required this.isActive,
    required this.focusNode,
    required this.onFocusSibling,
  });
  final CategoryNode node;
  final bool isActive;
  final FocusNode focusNode;
  final ValueChanged<int> onFocusSibling;

  @override
  State<_BarItem> createState() => _BarItemState();
}

class _BarItemState extends State<_BarItem> {
  final _panelController = AnchoredOverlayController();
  // Attached to the panel's first focusable; ArrowDown targets it.
  final _panelFirstFocusNode =
      FocusNode(debugLabel: 'megamenu-panel-first');
  bool _ringVisible = false;

  bool get _hasChildren => widget.node.children.isNotEmpty;

  @override
  void dispose() {
    _panelFirstFocusNode.dispose();
    super.dispose();
  }

  void _activate() {
    final isTouch = PointerKindObserver.lastKind.value == LastPointerKind.touch;
    if (isTouch && _hasChildren) {
      _panelController.open();
    } else {
      context.go('/categories/${widget.node.id}');
    }
  }

  void _openAndEnterPanel() {
    if (!_hasChildren) return;
    _panelController.open();
    // Let the panel mount, then move focus to its first leaf/header.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _panelFirstFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LastPointerKind>(
      valueListenable: PointerKindObserver.lastKind,
      builder: (context, kind, _) {
        final isTouch = kind == LastPointerKind.touch;
        return AnchoredOverlayPanel(
          controller: _panelController,
          openOnHover: _hasChildren,
          openOnFocus: _hasChildren,
          openOnTap: isTouch && _hasChildren,
          // The bar item's own FocusableActionDetector is the keyboard stop.
          triggerFocusSkipTraversal: true,
          exclusivityGroup: 'megamenu',
          offset: Offset.zero,
          trigger: _BarItemTrigger(
            node: widget.node,
            isActive: widget.isActive,
            isTouch: isTouch,
            focusNode: widget.focusNode,
            ringVisible: _ringVisible,
            onShowFocusHighlight: (v) {
              if (v != _ringVisible) setState(() => _ringVisible = v);
            },
            onActivate: _activate,
            onArrowDown: _openAndEnterPanel,
            onFocusSibling: widget.onFocusSibling,
          ),
          panelBuilder: (panelContext, close) {
            return MegaMenuPanel(
              active: widget.node,
              onDismiss: close,
              firstFocusNode: _panelFirstFocusNode,
              onTabPastLast: () {
                // Close without grabbing focus, then let traversal continue
                // to the next page focusable.
                _panelController.closeWithoutFocus();
                widget.focusNode.nextFocus();
              },
              // Close and return focus to the originating bar item.
              onShiftTabBeforeFirst: _panelController.close,
            );
          },
        );
      },
    );
  }
}

/// The focusable, keyboard-navigable bar item. Wraps the label+chevron in a
/// [MegaMenuFocusRing] (keyboard focus only) and maps Arrow/Enter/Space to the
/// §4.2 contract via a [FocusableActionDetector].
class _BarItemTrigger extends StatelessWidget {
  const _BarItemTrigger({
    required this.node,
    required this.isActive,
    required this.isTouch,
    required this.focusNode,
    required this.ringVisible,
    required this.onShowFocusHighlight,
    required this.onActivate,
    required this.onArrowDown,
    required this.onFocusSibling,
  });
  final CategoryNode node;
  final bool isActive;
  final bool isTouch;
  final FocusNode focusNode;
  final bool ringVisible;
  final ValueChanged<bool> onShowFocusHighlight;
  final VoidCallback onActivate;
  final VoidCallback onArrowDown;
  final ValueChanged<int> onFocusSibling;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasChildren = node.children.isNotEmpty;

    final body = MegaMenuFocusRing(
      show: ringVisible,
      child: _buildTriggerBody(context, cs, hasChildren),
    );

    final detector = FocusableActionDetector(
      focusNode: focusNode,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: onShowFocusHighlight,
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _MoveFocusIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _MoveFocusIntent(-1),
        const SingleActivator(LogicalKeyboardKey.enter):
            const _ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.space):
            const _ActivateIntent(),
        if (hasChildren)
          const SingleActivator(LogicalKeyboardKey.arrowDown):
              const _OpenPanelIntent(),
      },
      actions: <Type, Action<Intent>>{
        _MoveFocusIntent: CallbackAction<_MoveFocusIntent>(
          onInvoke: (i) {
            onFocusSibling(i.delta);
            return null;
          },
        ),
        _ActivateIntent: CallbackAction<_ActivateIntent>(
          onInvoke: (_) {
            onActivate();
            return null;
          },
        ),
        _OpenPanelIntent: CallbackAction<_OpenPanelIntent>(
          onInvoke: (_) {
            onArrowDown();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        label: node.name,
        hint: hasChildren ? 'Submenü açmak için Aşağı ok' : null,
        excludeSemantics: true,
        child: body,
      ),
    );

    // On touch the inner GestureDetector is dropped so the outer
    // AnchoredOverlayPanel tap-toggle wins; on pointer it routes to the PLP.
    if (isTouch) return detector;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go('/categories/${node.id}'),
      child: detector,
    );
  }

  Widget _buildTriggerBody(
    BuildContext context,
    ColorScheme cs,
    bool hasChildren,
  ) {
    return SizedBox(
      height: MegaMenuBar.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      node.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (hasChildren) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                height: 2,
                color:
                    isActive ? MoproTokens.primaryLight : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoveFocusIntent extends Intent {
  const _MoveFocusIntent(this.delta);
  final int delta;
}

class _ActivateIntent extends Intent {
  const _ActivateIntent();
}

class _OpenPanelIntent extends Intent {
  const _OpenPanelIntent();
}
