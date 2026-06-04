/// Formats a social-proof count (e.g. favorites) for a compact badge (P-004).
///
/// - `< 10`      → `''` (hidden — "♥ 3" is noise, worse than no count)
/// - `10–999`    → raw, e.g. `"247"`
/// - `1k–999k`   → `"1.2K"` (trailing `.0` dropped → `"1K"`)
/// - `≥ 1M`      → `"1.2M"`
///
/// Uses a period + `K`/`M` — universally read on social counts and avoids the
/// locale-compact ambiguity (Turkish compact renders thousands as "B"/bin).
String formatCompactCount(int count) {
  if (count < 10) return '';
  if (count < 1000) return '$count';
  if (count < 1000000) return '${_trim1(count / 1000.0)}K';
  return '${_trim1(count / 1000000.0)}M';
}

String _trim1(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
