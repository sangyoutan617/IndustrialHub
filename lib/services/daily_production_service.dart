import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/daily_production.dart';
import 'bottleneck_service.dart';
import 'data_event_service.dart';

class DailyProductionService {
  final SupabaseClient _client = Supabase.instance.client;
  final BottleneckService _bottleneckService = BottleneckService();

  /// Logs (or re-logs) production for one day. Reuses [BottleneckService]
  /// for the ceiling/bottleneck math rather than re-deriving it, and
  /// upserts on (factory_id, log_date) so re-logging the same day updates
  /// the existing row instead of creating a duplicate.
  Future<DailyProduction> logProduction({
    required int factoryId,
    required DateTime logDate,
    required int actualOutput,
    double downtimeHours = 0,
    bool isSimulated = false,
  }) async {
    final bottleneck = await _bottleneckService.computeForFactory(factoryId);

    final effectiveCeiling = bottleneck.hasData ? bottleneck.achievable : null;
    final utilisationPercent =
        (effectiveCeiling != null && effectiveCeiling > 0)
        ? (actualOutput / effectiveCeiling) * 100
        : null;

    final row = await _client
        .from('daily_production')
        .upsert({
          'factory_id': factoryId,
          'log_date': logDate.toIso8601String().substring(0, 10),
          'actual_output': actualOutput,
          'machine_capacity': bottleneck.hasData
              ? bottleneck.machineCapacity
              : null,
          'manpower_capacity': bottleneck.hasData
              ? bottleneck.manpowerCapacity
              : null,
          'effective_ceiling': effectiveCeiling,
          'bottleneck': bottleneck.hasData
              ? (bottleneck.limiter ?? bottleneck.bottleneckResource)
              : null,
          'utilisation_percent': utilisationPercent,
          'downtime_hours': downtimeHours,
          if (isSimulated) 'is_simulated': true,
        }, onConflict: 'factory_id,log_date')
        .select()
        .single();

    final result = DailyProduction.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.production,
    );
    return result;
  }

  Future<List<DailyProduction>> getTrend(int factoryId, {int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await _client
        .from('daily_production')
        .select()
        .eq('factory_id', factoryId)
        .gte('log_date', since.toIso8601String().substring(0, 10))
        .order('log_date', ascending: true);
    return (rows as List)
        .map((row) => DailyProduction.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Average output per *logged* day, grouped by calendar month. Averaging
  /// rather than summing is what makes this comparable to DOSM's monthly
  /// index: a month with only a handful of logged days would otherwise read
  /// as a collapse in output when it is really just fewer rows.
  Future<Map<DateTime, double>> getMonthlyAverageOutput(
    int factoryId, {
    required DateTime since,
  }) async {
    final rows = await _client
        .from('daily_production')
        .select('log_date, actual_output')
        .eq('factory_id', factoryId)
        .gte('log_date', since.toIso8601String().substring(0, 10))
        .order('log_date', ascending: true);

    final totals = <DateTime, double>{};
    final counts = <DateTime, int>{};
    for (final row in rows as List) {
      final map = row as Map<String, dynamic>;
      final date = DateTime.parse(map['log_date'] as String);
      final month = DateTime(date.year, date.month);
      totals[month] =
          (totals[month] ?? 0) + (map['actual_output'] as num).toDouble();
      counts[month] = (counts[month] ?? 0) + 1;
    }
    return {
      for (final entry in totals.entries)
        entry.key: entry.value / counts[entry.key]!,
    };
  }
}
