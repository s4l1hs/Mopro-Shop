import 'package:intl/intl.dart';

/// Formats [amountMinor] (integer minor units, divisor 100) to a
/// human-readable coin string.
///
/// [compact] = true  → "500,00 MC"     (pill, list items)
/// [compact] = false → "500,00 Mopro Coin" (balance card, detail)
String formatCoin(
  int amountMinor,
  String currency, {
  bool compact = true,
}) {
  final amount = amountMinor / 100.0;
  final formatted = NumberFormat('#,##0.00', 'tr_TR').format(amount);
  final symbol =
      compact ? _compactSymbol(currency) : _fullSymbol(currency);
  return '$formatted $symbol';
}

String _compactSymbol(String currency) {
  if (currency.endsWith('_COIN')) return 'MC';
  return currency;
}

String _fullSymbol(String currency) {
  if (currency.endsWith('_COIN')) return 'Mopro Coin';
  return currency;
}

/// Parses a "YYYYMM" string (e.g. "202601") into a [DateTime].
DateTime parsePeriod(String periodYyyymm) {
  final year = int.parse(periodYyyymm.substring(0, 4));
  final month = int.parse(periodYyyymm.substring(4, 6));
  return DateTime(year, month);
}

/// Formats a "YYYYMM" string to a Turkish month label ("Ocak 2026").
/// Requires [initializeDateFormatting('tr_TR')] to have been called.
String formatPeriodLabel(String periodYyyymm) {
  final dt = parsePeriod(periodYyyymm);
  return DateFormat('MMMM yyyy', 'tr_TR').format(dt);
}
