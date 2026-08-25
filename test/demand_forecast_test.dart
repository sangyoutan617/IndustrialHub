import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/demand_forecast.dart';

DemandForecast _forecast({
  int id = 1,
  int perDay = 100,
  DateTime? start,
  DateTime? end,
}) {
  return DemandForecast(
    demandId: id,
    factoryId: 1,
    productName: 'Widget',
    requiredPerDay: perDay,
    periodStart: start,
    periodEnd: end,
  );
}

void main() {
  final today = DateTime(2026, 6, 15);

  group('DemandForecast.isActiveOn', () {
    test('a forecast with no period is always active', () {
      expect(_forecast().isActiveOn(today), isTrue);
    });

    test('active when today is inside the period', () {
      final f = _forecast(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 30));
      expect(f.isActiveOn(today), isTrue);
    });

    test('inactive before the period starts', () {
      final f = _forecast(start: DateTime(2026, 7, 1), end: DateTime(2026, 7, 31));
      expect(f.isActiveOn(today), isFalse);
    });

    test('inactive after the period ends', () {
      final f = _forecast(start: DateTime(2026, 5, 1), end: DateTime(2026, 5, 31));
      expect(f.isActiveOn(today), isFalse);
    });

    test('both period boundaries are inclusive', () {
      final startDay = _forecast(
        start: DateTime(2026, 6, 15),
        end: DateTime(2026, 6, 30),
      );
      final endDay = _forecast(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 15),
      );
      expect(startDay.isActiveOn(today), isTrue);
      expect(endDay.isActiveOn(today), isTrue);
    });

    test('an open-ended start (only end set) is active up to the end', () {
      final f = _forecast(end: DateTime(2026, 6, 30));
      expect(f.isActiveOn(today), isTrue);
      expect(f.isActiveOn(DateTime(2026, 7, 1)), isFalse);
    });

    test('the time-of-day is ignored — compared date-only', () {
      final f = _forecast(start: DateTime(2026, 6, 15), end: DateTime(2026, 6, 15));
      expect(f.isActiveOn(DateTime(2026, 6, 15, 23, 59)), isTrue);
    });
  });

  group('DemandForecast.activeOn', () {
    test('keeps only the forecasts in effect today', () {
      final forecasts = [
        _forecast(id: 1), // no period -> active
        _forecast(id: 2, start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 30)), // active
        _forecast(id: 3, start: DateTime(2026, 7, 1)), // future -> inactive
        _forecast(id: 4, end: DateTime(2026, 5, 31)), // expired -> inactive
      ];
      final active = DemandForecast.activeOn(forecasts, today);
      expect(active.map((f) => f.demandId), [1, 2]);
    });

    test('empty in, empty out', () {
      expect(DemandForecast.activeOn(const [], today), isEmpty);
    });
  });
}
