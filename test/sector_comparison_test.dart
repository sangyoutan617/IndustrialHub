import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/ipi_benchmark.dart';
import 'package:industrial_hub/services/capacity_service.dart';

IpiBenchmark _ipi(int year, int month, double index) {
  return IpiBenchmark(
    date: DateTime(year, month),
    division: '10',
    productionIndex: index,
  );
}

void main() {
  group('buildSectorComparison', () {
    test('rebases both series to 100 at the first shared month', () {
      final comparison = CapacityService.buildSectorComparison(
        ipiTrend: [_ipi(2026, 1, 120), _ipi(2026, 2, 132)],
        factoryMonthlyOutput: {
          DateTime(2026, 1): 500,
          DateTime(2026, 2): 550,
        },
      )!;

      expect(comparison.points.first.factoryIndex, 100);
      expect(comparison.points.first.sectorIndex, 100);
      // Both grew 10%, so a factory in units/day and a sector in index points
      // land on the same rebased value.
      expect(comparison.points.last.factoryIndex, closeTo(110, 0.001));
      expect(comparison.points.last.sectorIndex, closeTo(110, 0.001));
    });

    test('reports growth against the base month, not the levels', () {
      final comparison = CapacityService.buildSectorComparison(
        ipiTrend: [_ipi(2026, 1, 100), _ipi(2026, 2, 95)],
        factoryMonthlyOutput: {
          DateTime(2026, 1): 400,
          DateTime(2026, 2): 440,
        },
      )!;

      expect(comparison.baseMonth, DateTime(2026, 1));
      expect(comparison.latestMonth, DateTime(2026, 2));
      expect(comparison.factoryChangePercent, closeTo(10, 0.001));
      expect(comparison.sectorChangePercent, closeTo(-5, 0.001));
    });

    test('skips months the factory never logged rather than reading them as '
        'zero output', () {
      final comparison = CapacityService.buildSectorComparison(
        ipiTrend: [
          _ipi(2026, 1, 100),
          _ipi(2026, 2, 110),
          _ipi(2026, 3, 120),
        ],
        factoryMonthlyOutput: {
          DateTime(2026, 1): 500,
          DateTime(2026, 3): 600,
        },
      )!;

      expect(comparison.points.length, 2);
      expect(
        comparison.points.map((p) => p.month),
        [DateTime(2026, 1), DateTime(2026, 3)],
      );
      expect(comparison.points.last.sectorIndex, closeTo(120, 0.001));
      expect(comparison.points.last.factoryIndex, closeTo(120, 0.001));
    });

    test('returns null when the overlap is a single month', () {
      final comparison = CapacityService.buildSectorComparison(
        ipiTrend: [_ipi(2026, 1, 100), _ipi(2026, 2, 110)],
        factoryMonthlyOutput: {DateTime(2026, 2): 500},
      );

      expect(comparison, isNull);
    });

    test('returns null when there is no overlap at all', () {
      final comparison = CapacityService.buildSectorComparison(
        ipiTrend: [_ipi(2026, 1, 100), _ipi(2026, 2, 110)],
        factoryMonthlyOutput: {
          DateTime(2025, 11): 500,
          DateTime(2025, 12): 520,
        },
      );

      expect(comparison, isNull);
    });

    test('returns null when the base month has nothing to divide by', () {
      final comparison = CapacityService.buildSectorComparison(
        ipiTrend: [_ipi(2026, 1, 100), _ipi(2026, 2, 110)],
        factoryMonthlyOutput: {
          DateTime(2026, 1): 0,
          DateTime(2026, 2): 550,
        },
      );

      expect(comparison, isNull);
    });

    test('matches on calendar month regardless of day-of-month in the reading',
        () {
      final comparison = CapacityService.buildSectorComparison(
        ipiTrend: [
          IpiBenchmark(
            date: DateTime(2026, 1, 31),
            division: '10',
            productionIndex: 100,
          ),
          IpiBenchmark(
            date: DateTime(2026, 2, 28),
            division: '10',
            productionIndex: 110,
          ),
        ],
        factoryMonthlyOutput: {
          DateTime(2026, 1): 500,
          DateTime(2026, 2): 500,
        },
      )!;

      expect(comparison.points.length, 2);
      expect(comparison.factoryChangePercent, closeTo(0, 0.001));
      expect(comparison.sectorChangePercent, closeTo(10, 0.001));
    });
  });
}
