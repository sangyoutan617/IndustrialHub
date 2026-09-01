import 'package:intl/intl.dart';

final _wholeNumber = NumberFormat('#,##0', 'en_US');
final _upToOneDecimal = NumberFormat('#,##0.#', 'en_US');
final _upToTwoDecimals = NumberFormat('#,##0.##', 'en_US');
final _oneDecimal = NumberFormat('0.0', 'en_US');
final _money = NumberFormat('#,##0.00', 'en_US');
final _shortDate = DateFormat('d MMM y');
final _monthYear = DateFormat('MMM y');

String formatUnits(num v) {
  final formatted = v == v.roundToDouble()
      ? _wholeNumber.format(v)
      : _upToOneDecimal.format(v);
  return '$formatted units';
}

String formatNumber(num v) => _upToTwoDecimals.format(v);

String formatRate(num v) => _money.format(v);

String formatWhole(num v) => _wholeNumber.format(v);

String formatPercent(num v) => '${_oneDecimal.format(v)}%';

String formatDate(DateTime d) => _shortDate.format(d);

String formatMonth(DateTime d) => _monthYear.format(d);

String formatDays(num v) => '${_oneDecimal.format(v)} days';

String formatCurrency(num v) => 'RM ${_money.format(v)}';

String formatPoNumber(int poId) => 'PO-${poId.toString().padLeft(4, '0')}';
