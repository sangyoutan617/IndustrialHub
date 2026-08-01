import 'package:intl/intl.dart';

final _wholeNumber = NumberFormat('#,##0');
final _upToOneDecimal = NumberFormat('#,##0.#');
final _upToTwoDecimals = NumberFormat('#,##0.##');
final _oneDecimal = NumberFormat('0.0');
final _shortDate = DateFormat('d MMM y');

/// "856 units" — whole numbers render with no decimal, fractional values
/// keep at most one decimal place.
String formatUnits(num v) {
  final formatted = v == v.roundToDouble()
      ? _wholeNumber.format(v)
      : _upToOneDecimal.format(v);
  return '$formatted units';
}

/// General-purpose number formatting with thousands separators and up to
/// two decimal places (trailing zeros trimmed): 1234 -> "1,234",
/// 1234.5 -> "1,234.5".
String formatNumber(num v) => _upToTwoDecimals.format(v);

/// Expects [v] already on a 0-100 scale (e.g. 85.3, not 0.853):
/// "85.3%".
String formatPercent(num v) => '${_oneDecimal.format(v)}%';

/// "24 Jul 2026".
String formatDate(DateTime d) => _shortDate.format(d);

/// "1.2 days".
String formatDays(num v) => '${_oneDecimal.format(v)} days';
