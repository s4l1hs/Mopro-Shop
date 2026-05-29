import 'package:flutter/material.dart';
import 'package:mopro/design/tokens.dart';

/// Keyboard-only focus indicator for the mega menu (§4.1).
///
/// Paints a 2dp brand-orange outline with a 1dp inset white separator (so the
/// ring reads on any background) as a non-layout-affecting overlay on top of
/// [child] when [show] is true. Callers drive [show] from a
/// `FocusableActionDetector`'s `onShowFocusHighlight`, which is true only for
/// keyboard/traversal focus — never for pointer hover or touch — so the ring
/// is hidden when focus is acquired by a pointer click.
class MegaMenuFocusRing extends StatelessWidget {
  const MegaMenuFocusRing({
    required this.show,
    required this.child,
    super.key,
    this.radius = 4,
    this.padding = EdgeInsets.zero,
  });

  final bool show;
  final Widget child;

  /// Corner radius of the ring.
  final double radius;

  /// Inset between the ring and [child] (panel rows use 4dp horizontal so the
  /// ring doesn't crowd the text).
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = padding == EdgeInsets.zero
        ? child
        : Padding(padding: padding, child: child);

    if (!show) return content;

    return Stack(
      children: [
        content,
        // 2dp brand-orange outline.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius + 1),
                border: Border.all(
                  color: MoproTokens.primaryLight,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        // 1dp white separator just inside the orange.
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
