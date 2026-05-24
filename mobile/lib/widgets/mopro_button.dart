import 'package:flutter/material.dart';
import 'package:mopro/design/tokens.dart';

enum MoproButtonVariant {
  filled,
  tonal,
  outlined,
  ghost,
  destructive,
  link,
}

enum MoproButtonSize { sm, md, lg }

class MoproButton extends StatelessWidget {
  const MoproButton({
    required this.label,
    required this.onPressed,
    this.variant = MoproButtonVariant.filled,
    this.size = MoproButtonSize.md,
    this.leading,
    this.trailing,
    this.loading = false,
    this.fullWidth = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final MoproButtonVariant variant;
  final MoproButtonSize size;
  final Widget? leading;
  final Widget? trailing;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (minH, hPad, fontSize) = switch (size) {
      MoproButtonSize.sm => (36.0, 12.0, 13.0),
      MoproButtonSize.md => (48.0, 16.0, 15.0),
      MoproButtonSize.lg => (56.0, 20.0, 17.0),
    };

    Widget content = loading
        ? SizedBox.square(
            dimension: fontSize + 2,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _fgColor(cs),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Text(label),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          );

    if (fullWidth) {
      content = Center(child: content);
    }

    final style = _style(cs, minH, hPad, fontSize);

    return switch (variant) {
      MoproButtonVariant.filled ||
      MoproButtonVariant.destructive =>
        FilledButton(
          onPressed: loading ? null : onPressed,
          style: style,
          child: content,
        ),
      MoproButtonVariant.tonal => FilledButton.tonal(
          onPressed: loading ? null : onPressed,
          style: style,
          child: content,
        ),
      MoproButtonVariant.outlined => OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: style,
          child: content,
        ),
      MoproButtonVariant.ghost ||
      MoproButtonVariant.link =>
        TextButton(
          onPressed: loading ? null : onPressed,
          style: style,
          child: content,
        ),
    };
  }

  Color _fgColor(ColorScheme cs) => switch (variant) {
        MoproButtonVariant.filled => cs.onPrimary,
        MoproButtonVariant.destructive => Colors.white,
        MoproButtonVariant.tonal => cs.onSecondaryContainer,
        _ => cs.primary,
      };

  ButtonStyle _style(
    ColorScheme cs,
    double minH,
    double hPad,
    double fontSize,
  ) {
    final radius = BorderRadius.circular(MoproTokens.radiusMd);
    final minSize = Size(fullWidth ? double.infinity : 0, minH);
    final padding =
        EdgeInsets.symmetric(horizontal: hPad, vertical: (minH - fontSize) / 2);

    return switch (variant) {
      MoproButtonVariant.filled => FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          minimumSize: minSize,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      MoproButtonVariant.destructive => FilledButton.styleFrom(
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
          minimumSize: minSize,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      MoproButtonVariant.tonal => FilledButton.styleFrom(
          backgroundColor: cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
          minimumSize: minSize,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      MoproButtonVariant.outlined => OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.outline),
          minimumSize: minSize,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      MoproButtonVariant.ghost => TextButton.styleFrom(
          foregroundColor: cs.onSurface,
          minimumSize: minSize,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
        ),
      MoproButtonVariant.link => TextButton.styleFrom(
          foregroundColor: cs.primary,
          minimumSize: minSize,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
    };
  }
}
