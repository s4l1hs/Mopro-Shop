import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/anchored_overlay_panel.dart';
import 'package:mopro/design/responsive/pointer_kind.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_panel.dart';

/// Persistent top-level category bar mounted directly under the `WebHeader`
/// at `>=768` widths. Below 768dp the bar is NOT in the widget tree — the
/// shell decides visibility, not the bar.
///
/// Built as a consumer of `AnchoredOverlayPanel` (Session 4b): each bar item
/// wraps in a panel that opens on hover/focus, with `exclusivityGroup:
/// "megamenu"` so hovering from one category to the next opens the new panel
/// and closes the old without a flash of two panels.
///
/// Tap behavior (Session 4d §4) depends on the last observed pointer kind:
///
/// - **Pointer (mouse / trackpad / stylus):** label tap routes to the
///   category PLP; hover or focus opens the panel.
/// - **Touch:** label tap OPENS the panel; tapping the active item again
///   closes it; routing happens only through panel content (leaves +
///   "Tümünü gör").
///
/// Detection lives in `PointerKindObserver` (installed in `main.dart`);
/// the bar reads it via `ValueListenableBuilder` so each bar item
/// rebuilds when the kind changes (rare in practice — fires on the
/// FIRST pointer event after install). Escape inside the panel always
/// returns focus to the bar item regardless of pointer kind.
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

/// Horizontal scroller with 24dp edge fade masks on both sides. The fades use
/// `ShaderMask` over the scroll view; the scroll view itself uses a controller
/// so future programmatic scroll-to-active can hook in without restructuring.
class _BarScroller extends StatefulWidget {
  const _BarScroller({required this.roots});
  final List<CategoryNode> roots;

  @override
  State<_BarScroller> createState() => _BarScrollerState();
}

class _BarScrollerState extends State<_BarScroller> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
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
          );
        },
      ),
    );
  }

  bool _isActiveRoute(BuildContext context, CategoryNode node) {
    final loc = GoRouterState.of(context).uri.toString();
    return loc.startsWith('/categories/${node.id}');
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({required this.node, required this.isActive});
  final CategoryNode node;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;

    // Rebuild on pointer-kind change. The decision below — whether the
    // bar item's label tap routes (pointer) or opens the panel (touch)
    // — is recomputed each time.
    return ValueListenableBuilder<LastPointerKind>(
      valueListenable: PointerKindObserver.lastKind,
      builder: (context, kind, _) {
        final isTouch = kind == LastPointerKind.touch;
        return AnchoredOverlayPanel(
          openOnHover: hasChildren,
          openOnFocus: hasChildren,
          // Touch: AnchoredOverlayPanel handles the tap as a toggle.
          // Pointer: trigger's own GestureDetector routes; the panel
          // opens via hover/focus only.
          openOnTap: isTouch && hasChildren,
          exclusivityGroup: 'megamenu',
          offset: Offset.zero,
          trigger: _BarItemTrigger(
            node: node,
            isActive: isActive,
            // On touch the trigger's inner GestureDetector is dropped
            // so the outer panel-toggle wins; on pointer it routes to
            // the PLP and the panel stays driven by hover/focus.
            isTouch: isTouch,
          ),
          panelBuilder: (panelContext, close) {
            return MegaMenuPanel(active: node, onDismiss: close);
          },
        );
      },
    );
  }
}

class _BarItemTrigger extends StatelessWidget {
  const _BarItemTrigger({
    required this.node,
    required this.isActive,
    required this.isTouch,
  });
  final CategoryNode node;
  final bool isActive;
  final bool isTouch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasChildren = node.children.isNotEmpty;

    // On touch the inner GestureDetector is dropped entirely so the outer
    // AnchoredOverlayPanel's tap-toggle wins; on pointer the inner GD
    // routes to the PLP and the panel opens via hover/focus.
    final inner = SizedBox(
      height: MegaMenuBar.height,
      child: _buildTriggerBody(context, cs, hasChildren),
    );
    if (isTouch) {
      return inner;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Pointer: label tap routes to category PLP — does NOT open the panel.
      onTap: () => context.go('/categories/${node.id}'),
      child: inner,
    );
  }

  Widget _buildTriggerBody(
    BuildContext context,
    ColorScheme cs,
    bool hasChildren,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // IntrinsicWidth + stretch so the 2dp indicator spans exactly the
      // label+chevron width, not the unbounded ListView item width.
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
            // 2dp brand-orange bottom indicator on the active route.
            Container(
              height: 2,
              color: isActive
                  ? MoproTokens.primaryLight
                  : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
