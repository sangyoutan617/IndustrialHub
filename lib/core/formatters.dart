import 'package:intl/intl.dart';

// Every NumberFormat here is pinned to 'en_US' rather than following the
// ambient platform locale. That's load-bearing, not cosmetic: on a locale
// where the *decimal* separator is itself a comma (e.g. de, fr), an
// unpinned format's grouping character wouldn't reliably be ',' — pinning
// guarantees the character _spaced() replaces below is always the grouping
// separator, never a decimal point, regardless of device locale.
final _wholeNumber = NumberFormat('#,##0', 'en_US');
final _upToOneDecimal = NumberFormat('#,##0.#', 'en_US');
final _upToTwoDecimals = NumberFormat('#,##0.##', 'en_US');
final _oneDecimal = NumberFormat('0.0', 'en_US');
final _money = NumberFormat('#,##0.00', 'en_US');
final _shortDate = DateFormat('d MMM y');

/// House style is a space, not a comma, between thousands groups:
/// "40 000" rather than "40,000".
String _spaced(String s) => s.replaceAll(',', ' ');

/// "856 units" — whole numbers render with no decimal, fractional values
/// keep at most one decimal place.
String formatUnits(num v) {
  final formatted = v == v.roundToDouble()
      ? _wholeNumber.format(v)
      : _upToOneDecimal.format(v);
  return '${_spaced(formatted)} units';
}

/// General-purpose number formatting with space-separated thousands and up
/// to two decimal places (trailing zeros trimmed): 1234 -> "1 234",
/// 1234.5 -> "1 234.5".
String formatNumber(num v) => _spaced(_upToTwoDecimals.format(v));

/// Always rounds to a whole number with space-separated thousands:
/// 1234 -> "1 234", 1234.7 -> "1 235". Use where a display previously
/// rounded via `.toStringAsFixed(0)` and must keep that fixed precision —
/// formatNumber/formatUnits would show up to 1-2 decimal places instead,
/// silently changing precision, not just adding a separator.
String formatWhole(num v) => _spaced(_wholeNumber.format(v));

/// Expects [v] already on a 0-100 scale (e.g. 85.3, not 0.853):
/// "85.3%".
String formatPercent(num v) => '${_oneDecimal.format(v)}%';

/// "24 Jul 2026".
String formatDate(DateTime d) => _shortDate.format(d);

/// "1.2 days".
String formatDays(num v) => '${_oneDecimal.format(v)} days';

/// Malaysian Ringgit with space-separated thousands and two decimals:
/// 1234.5 -> "RM 1 234.50". Currency across the app is RM.
String formatCurrency(num v) => 'RM ${_spaced(_money.format(v))}';
