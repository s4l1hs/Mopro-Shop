import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Semantic-structure checks the harness can run.
enum A11yCheck {
  /// Tappable widget whose merged semantics has no accessible label.
  missingSemanticLabel,

  /// Tappable widget smaller than the 44x44 logical-px minimum hit target.
  smallHitTarget,

  /// Tappable widget whose semantics omits the button role flag.
  missingButtonRole;

  /// The checks run by default. (The prompt also lists liveRegion / focus-order
  /// / page-title checks; those are covered at the route + widget level by
  /// dedicated tests in this PR rather than this tappable-walk set.)
  static const Set<A11yCheck> all = {
    missingSemanticLabel,
    smallHitTarget,
    missingButtonRole,
  };
}

enum A11ySeverity { error, warning, info }

class A11yViolation {
  const A11yViolation({
    required this.check,
    required this.severity,
    required this.widgetType,
    required this.message,
    this.widgetKey,
    this.bounds,
    this.semanticPath,
  });

  final A11yCheck check;
  final A11ySeverity severity;
  final String widgetType;
  final String? widgetKey;
  final Rect? bounds;
  final String? semanticPath;
  final String message;
}

class A11yAuditReport {
  A11yAuditReport(this.violations);

  final List<A11yViolation> violations;

  List<A11yViolation> get errorsOnly =>
      violations.where((v) => v.severity == A11ySeverity.error).toList();

  bool get isClean => errorsOnly.isEmpty;

  int countOf(A11ySeverity s) =>
      violations.where((v) => v.severity == s).length;

  String toMarkdown() {
    if (violations.isEmpty) return '_No violations._\n';
    final byCheck = <A11yCheck, List<A11yViolation>>{};
    for (final v in violations) {
      byCheck.putIfAbsent(v.check, () => []).add(v);
    }
    final b = StringBuffer();
    for (final entry in byCheck.entries) {
      b
        ..writeln('### ${entry.key.name} (${entry.value.length})\n')
        ..writeln('| Severity | Widget | Key | Bounds | Detail |')
        ..writeln('| --- | --- | --- | --- | --- |');
      for (final v in entry.value) {
        final bounds = v.bounds == null
            ? '—'
            : '${v.bounds!.width.toStringAsFixed(0)}x'
                '${v.bounds!.height.toStringAsFixed(0)}';
        b.writeln(
          '| ${v.severity.name} | ${v.widgetType} | '
          '${v.widgetKey ?? '—'} | $bounds | ${v.message} |',
        );
      }
      b.writeln();
    }
    return b.toString();
  }
}

/// Read-only walker that flags semantic-structure violations under a finder.
class A11yAuditHarness {
  static Future<A11yAuditReport> audit(
    WidgetTester tester,
    Finder rootFinder, {
    Set<A11yCheck> checks = A11yCheck.all,
    Set<String> ignoreKeys = const {},
  }) async {
    final handle = tester.ensureSemantics();
    final violations = <A11yViolation>[];
    final rootElement = rootFinder.evaluate().first;

    // Walk the element tree once, counting only the OUTERMOST tappable in any
    // nested tappable chain (the widget a user actually targets — an
    // IconButton's inner InkResponse is skipped).
    // ignore: avoid_positional_boolean_parameters
    void visit(Element el, bool insideTappable) {
      final widget = el.widget;
      var childrenInside = insideTappable;
      if (_hasTapHandler(widget) && !insideTappable) {
        childrenInside = true;
        _checkTappable(el, widget, checks, ignoreKeys, violations);
      }
      el.visitChildren((child) => visit(child, childrenInside));
    }

    visit(rootElement, false);
    handle.dispose();
    return A11yAuditReport(violations);
  }

  static bool _hasTapHandler(Widget w) {
    if (w is InkResponse) return w.onTap != null || w.onLongPress != null;
    if (w is InkWell) return w.onTap != null || w.onLongPress != null;
    if (w is GestureDetector) return w.onTap != null || w.onLongPress != null;
    return false;
  }

  static void _checkTappable(
    Element el,
    Widget widget,
    Set<A11yCheck> checks,
    Set<String> ignoreKeys,
    List<A11yViolation> out,
  ) {
    final keyStr = widget.key?.toString();
    if (keyStr != null && ignoreKeys.contains(keyStr)) return;

    final render = el.renderObject;
    Rect? bounds;
    Size? size;
    if (render is RenderBox && render.hasSize) {
      size = render.size;
      bounds = render.localToGlobal(Offset.zero) & size;
    }

    final data = _semanticsFor(render)?.getSemanticsData();
    // A tappable is "named" for AT if it has a label OR a tooltip (IconButton's
    // tooltip lands on SemanticsData.tooltip, which screen readers announce).
    final hasName = (data?.label.trim().isNotEmpty ?? false) ||
        (data?.tooltip.trim().isNotEmpty ?? false);
    final type = widget.runtimeType.toString();

    if (checks.contains(A11yCheck.missingSemanticLabel) && !hasName) {
      out.add(
        A11yViolation(
          check: A11yCheck.missingSemanticLabel,
          severity: A11ySeverity.error,
          widgetType: type,
          widgetKey: keyStr,
          bounds: bounds,
          message: 'Tappable $type has no accessible label.',
        ),
      );
    }

    if (checks.contains(A11yCheck.smallHitTarget) &&
        size != null &&
        (size.width < 44 || size.height < 44)) {
      out.add(
        A11yViolation(
          check: A11yCheck.smallHitTarget,
          severity: A11ySeverity.warning,
          widgetType: type,
          widgetKey: keyStr,
          bounds: bounds,
          message: 'Hit target ${size.width.toStringAsFixed(0)}x'
              '${size.height.toStringAsFixed(0)} is below 44x44.',
        ),
      );
    }

    if (checks.contains(A11yCheck.missingButtonRole) &&
        data != null &&
        !_isButtonLike(data)) {
      out.add(
        A11yViolation(
          check: A11yCheck.missingButtonRole,
          severity: A11ySeverity.info,
          widgetType: type,
          widgetKey: keyStr,
          bounds: bounds,
          message: 'Tappable $type is not exposed with a button/link role.',
        ),
      );
    }
  }

  static bool _isButtonLike(SemanticsData data) {
    // ignore: deprecated_member_use
    return data.hasFlag(SemanticsFlag.isButton) ||
        // ignore: deprecated_member_use
        data.hasFlag(SemanticsFlag.isLink) ||
        // ignore: deprecated_member_use
        data.hasFlag(SemanticsFlag.isTextField);
  }

  /// Nearest semantics node at or above [render] (semantics may merge upward).
  static SemanticsNode? _semanticsFor(RenderObject? render) {
    var r = render;
    while (r != null) {
      final node = r.debugSemantics;
      if (node != null) return node;
      r = r.parent;
    }
    return null;
  }
}
