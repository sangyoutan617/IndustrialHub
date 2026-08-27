import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/core/formatters.dart';

void main() {
  group('formatNumber', () {
    test('groups thousands with a space, not a comma', () {
      expect(formatNumber(40000), '40 000');
    });

    test('preserves a fractional part instead of dropping it', () {
      expect(formatNumber(1234.5), '1 234.5');
    });

    test('trims trailing zeros beyond the decimal point', () {
      expect(formatNumber(1234.50), '1 234.5');
    });

    test('a number below the grouping threshold has no space at all', () {
      expect(formatNumber(42), '42');
    });

    test('groups millions with two separators', () {
      expect(formatNumber(1234567), '1 234 567');
    });
  });

  group('formatUnits', () {
    test('whole numbers render with no decimal', () {
      expect(formatUnits(856), '856 units');
    });

    test('fractional values keep one decimal place, still space-grouped', () {
      expect(formatUnits(40000.5), '40 000.5 units');
    });
  });

  group('formatWhole', () {
    test('rounds to the nearest whole number', () {
      expect(formatWhole(1234.7), '1 235');
    });

    test('rounds down when the fraction is below .5', () {
      expect(formatWhole(1234.2), '1 234');
    });

    test('space-groups a whole-number result', () {
      expect(formatWhole(40000), '40 000');
    });
  });

  group('formatCurrency', () {
    test('prefixes RM and space-groups the whole part', () {
      expect(formatCurrency(1234.5), 'RM 1 234.50');
    });

    test('always shows two decimal places', () {
      expect(formatCurrency(40000), 'RM 40 000.00');
    });
  });

  group('formatPercent and formatDays', () {
    test('formatPercent keeps one decimal, no grouping needed under 100', () {
      expect(formatPercent(85.3), '85.3%');
    });

    test('formatDays keeps one decimal', () {
      expect(formatDays(1.2), '1.2 days');
    });
  });
}
