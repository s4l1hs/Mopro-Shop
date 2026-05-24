/// Money formatting utilities — exact port of web/lib/money.ts.
/// All amounts use integer minor units (smallest denomination).
abstract final class MoneyUtils {
  MoneyUtils._();

  /// Monthly cashback coin in minor units.
  /// Formula: (priceMinor × commissionPctBps) ÷ 156000 (integer truncation).
  /// Derivation: price × bps/10000 × 5000/10000 / 12 = price × bps / 156000
  static int cashbackMonthlyMinor(int priceMinor, int commissionPctBps) =>
      (priceMinor * commissionPctBps) ~/ 156000;

  /// Format minor units to a human-readable string with Turkish locale formatting.
  /// Uses '.' as thousands separator and ',' as decimal separator.
  static String formatMinor(int minor, {String currency = 'TRY'}) {
    final major = minor / 100.0;
    final formatted = _formatTR(major);
    return switch (currency) {
      'TRY' => '₺$formatted',
      'TRY_COIN' => '$formatted ₺C',
      'EUR' => '€$formatted',
      'USD' => '\$$formatted',
      _ => '$formatted $currency',
    };
  }

  /// Returns just the formatted number without currency symbol.
  static String formatNumber(int minor) => _formatTR(minor / 100.0);

  static String _formatTR(double value) {
    final isWhole = value == value.truncateToDouble();
    if (isWhole) {
      return _insertDots(value.toInt().toString());
    }
    final parts = value.toStringAsFixed(2).split('.');
    return '${_insertDots(parts[0])},${parts[1]}';
  }

  static String _insertDots(String s) {
    if (s.length <= 3) return s;
    final buf = StringBuffer();
    final mod = s.length % 3;
    for (var i = 0; i < s.length; i++) {
      if (i != 0 && (i - mod) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
