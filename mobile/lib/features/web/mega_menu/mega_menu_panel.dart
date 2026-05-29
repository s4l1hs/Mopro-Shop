import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/design/widgets/responsive_network_image.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_focus_ring.dart';
import 'package:mopro/features/web/mega_menu/promo_image_placeholder.dart';
import 'package:mopro_api/mopro_api.dart';

/// Full-width panel opened from `MegaMenuBar` for the active top-level
/// category. Layout (Session 4c/4d): `surface` bg, bottom-only 8dp radius,
/// 6dp shadow, content clamped + centered; 4 subcategory columns, or 3+1 when
/// a `promoSlot` is present.
///
/// ## Keyboard contract (Session 4e §4.3)
///
/// Focus traverses **column-major** (`OrderedTraversalPolicy` + per-row
/// `NumericFocusOrder`): col1 header → col1 leaves → col1 "Tümünü gör" → col2
/// header → … → promo CTA. Every row is a keyboard-focusable button with a
/// [MegaMenuFocusRing] and a semantic label.
///
/// - **Escape** closes and returns focus to the bar item (handled upstream by
///   `AnchoredOverlayPanel`).
/// - **Tab past the last focusable** hits a trailing sentinel that closes the
///   panel and yields focus onward ([onTabPastLast]).
/// - **Shift+Tab before the first focusable** hits a leading sentinel that
///   closes the panel and returns focus to the bar item
///   ([onShiftTabBeforeFirst]).
///
/// [firstFocusNode] is attached to the first leaf of the first column (the
/// Arrow-Down target from the bar); it falls back to the first header when the
/// panel has no leaves.
class MegaMenuPanel extends StatelessWidget {
  const MegaMenuPanel({
    required this.active,
    required this.onDismiss,
    super.key,
    this.firstFocusNode,
    this.onTabPastLast,
    this.onShiftTabBeforeFirst,
  });

  final CategoryNode active;
  final VoidCallback onDismiss;
  final FocusNode? firstFocusNode;
  final VoidCallback? onTabPastLast;
  final VoidCallback? onShiftTabBeforeFirst;

  static const int _maxLeavesPerColumn = 8;
  static const int _columnCount = 4;
  static const int _columnCountWithPromo = 3;

  void _go(BuildContext context, int id) {
    onDismiss();
    context.go('/categories/$id');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subcats = active.children;
    final promo = active.promoSlot;

    return Material(
      elevation: 6,
      color: cs.surface,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant),
            left: BorderSide(color: cs.outlineVariant),
            right: BorderSide(color: cs.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Semantics(
          container: true,
          label: 'Category submenu for ${active.name}',
          child: subcats.isEmpty
              ? _EmptyState()
              : FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: CenteredContentColumn(
                    child: _buildBody(context, subcats, promo),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<CategoryNode> subcats,
    CategoryPromoSlot? promo,
  ) {
    final columnCount = promo != null ? _columnCountWithPromo : _columnCount;

    // Distribute subcategories across columns left-to-right.
    final columns = <List<CategoryNode>>[
      for (var i = 0; i < columnCount; i++) <CategoryNode>[],
    ];
    for (var i = 0; i < subcats.length; i++) {
      columns[i % columnCount].add(subcats[i]);
    }

    // Column-major focus order. ArrowDown target = first leaf (else first
    // header).
    final anyLeaves = subcats.any((s) => s.children.isNotEmpty);
    final assigner = _FirstFocusAssigner(
      node: firstFocusNode,
      attachToLeaf: anyLeaves,
    );
    var order = 1;

    final columnWidgets = <Widget>[];
    for (var c = 0; c < columns.length; c++) {
      final colChildren = <Widget>[];
      for (final subcat in columns[c]) {
        colChildren.add(
          _PanelRow(
            order: order++,
            label: subcat.name,
            focusNode: assigner.takeFor(isLeaf: false),
            onTap: () => _go(context, subcat.id),
            isHeader: true,
          ),
        );
        for (final leaf in subcat.children.take(_maxLeavesPerColumn)) {
          colChildren.add(
            _PanelRow(
              order: order++,
              label: leaf.name,
              focusNode: assigner.takeFor(isLeaf: true),
              onTap: () => _go(context, leaf.id),
            ),
          );
        }
        if (subcat.children.length > _maxLeavesPerColumn) {
          colChildren.add(
            _PanelRow(
              order: order++,
              label: 'Tümünü gör: ${subcat.name}',
              onTap: () => _go(context, subcat.id),
              isSeeAll: true,
            ),
          );
        }
        colChildren.add(const SizedBox(height: 16));
      }
      columnWidgets.add(
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: colChildren,
          ),
        ),
      );
      if (c < columns.length - 1 || promo != null) {
        columnWidgets.add(const SizedBox(width: 32));
      }
    }

    if (promo != null) {
      columnWidgets.add(
        Expanded(
          child: _PromoColumn(
            promo: promo,
            order: order++,
            onTap: () {
              onDismiss();
              context.go(promo.deepLink);
            },
          ),
        ),
      );
    }

    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: columnWidgets,
        ),
        // Leading sentinel (Shift+Tab before first focusable).
        _Sentinel(order: 0, onFocused: onShiftTabBeforeFirst),
        // Trailing sentinel (Tab past last focusable).
        _Sentinel(order: order + 1000, onFocused: onTabPastLast),
      ],
    );
  }
}

/// Tracks the first-focusable assignment so [MegaMenuPanel.firstFocusNode]
/// lands on the first leaf (the Arrow-Down target), or the first header when
/// the panel has no leaves.
class _FirstFocusAssigner {
  _FirstFocusAssigner({required this.node, required this.attachToLeaf});
  final FocusNode? node;
  final bool attachToLeaf;
  bool _taken = false;

  FocusNode? takeFor({required bool isLeaf}) {
    if (_taken || node == null) return null;
    if (attachToLeaf == isLeaf) {
      _taken = true;
      return node;
    }
    return null;
  }
}

/// A keyboard-focusable panel row (header, leaf, or "Tümünü gör"). Wraps its
/// label in a [MegaMenuFocusRing], maps Enter/Space to [onTap], and carries a
/// [NumericFocusOrder] for column-major traversal + a semantic button label.
class _PanelRow extends StatefulWidget {
  const _PanelRow({
    required this.order,
    required this.label,
    required this.onTap,
    this.focusNode,
    this.isHeader = false,
    this.isSeeAll = false,
  });

  final int order;
  final String label;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool isHeader;
  final bool isSeeAll;

  @override
  State<_PanelRow> createState() => _PanelRowState();
}

class _PanelRowState extends State<_PanelRow> {
  bool _ring = false;

  TextStyle _style(ColorScheme cs) {
    if (widget.isHeader) {
      return const TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    }
    if (widget.isSeeAll) {
      return const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: MoproTokens.primaryLight,
      );
    }
    return TextStyle(fontSize: 14, color: cs.onSurfaceVariant);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.order.toDouble()),
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) {
          if (v != _ring) setState(() => _ring = v);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          label: widget.label,
          excludeSemantics: true,
          child: MegaMenuFocusRing(
            show: _ring,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Padding(
                padding: EdgeInsets.only(
                  top: widget.isHeader ? 4 : 0,
                  bottom: widget.isHeader ? 8 : 0,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(widget.label, style: _style(cs)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Zero-size focus stop used to detect Tab-past-last / Shift+Tab-before-first.
/// On gaining focus it invokes [onFocused] (close + yield/return focus).
class _Sentinel extends StatelessWidget {
  const _Sentinel({required this.order, this.onFocused});
  final int order;
  final VoidCallback? onFocused;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order.toDouble()),
      child: Focus(
        skipTraversal: false,
        onFocusChange: (focused) {
          if (focused) onFocused?.call();
        },
        child: const SizedBox.shrink(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'mega_menu.empty_children'.tr(),
          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// The "+1" of the 3+1 layout. One keyboard focus stop (the CTA) per §4.3:
/// the inner image/button taps are excluded from traversal so the whole promo
/// is a single focusable.
class _PromoColumn extends StatefulWidget {
  const _PromoColumn({
    required this.promo,
    required this.order,
    required this.onTap,
  });

  final CategoryPromoSlot promo;
  final int order;
  final VoidCallback onTap;

  @override
  State<_PromoColumn> createState() => _PromoColumnState();
}

class _PromoColumnState extends State<_PromoColumn> {
  bool _ring = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.order.toDouble()),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) {
          if (v != _ring) setState(() => _ring = v);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          label: widget.promo.title,
          excludeSemantics: true,
          child: MegaMenuFocusRing(
            show: _ring,
            radius: 8,
            // Inner taps don't add focus stops — the promo is one focusable.
            child: ExcludeFocus(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: InkWell(
                      onTap: widget.onTap,
                      borderRadius: BorderRadius.circular(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: ResponsiveNetworkImage(
                            imageUrl: widget.promo.imageUrl,
                            placeholder: (_, __) =>
                                Container(color: cs.surfaceContainerHighest),
                            errorWidget: (_, __, ___) =>
                                const PromoImagePlaceholder(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      widget.promo.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: widget.onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: MoproTokens.primaryLight,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text('mega_menu.promo.cta'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
