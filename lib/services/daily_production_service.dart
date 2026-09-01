import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/daily_production.dart';
import 'bottleneck_service.dart';
import 'data_event_service.dart';

class DailyProductionService {
  final SupabaseClient _client = Supabase.instance.client;
  final BottleneckService _bottleneckService = BottleneckService();

  Future<DailyProduction> logProduction({
    required int factoryId,
    required int productId,
    required DateTime logDate,
    required int actualOutput,
    double downtimeHours = 0,
    bool isSimulated = false,
  }) async {
    final bottleneck = await _bottleneckService.computeForProduct(
      factoryId,
      productId,
    );

    final effectiveCeiling = bottleneck.hasData ? bottleneck.achievable : null;
    final utilisationPercent =
        (effectiveCeiling != null && effectiveCeiling > 0)
        ? (actualOutput / effectiveCeiling) * 100
        : null;

    final row = await _client
        .from('daily_production')
        .upsert({
          'factory_id': factoryId,
          'product_id': productId,
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
        }, onConflict: 'factory_id,product_id,log_date')
        .select()
        .single();

    final result = DailyProduction.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.production,
    );
    return result;
  }

  Future<void> logHistoricalBatch({
    required int factoryId,
    required int productId,
    required List<({DateTime logDate, int actualOutput, double downtimeHours})>
    days,
  }) async {
    if (days.isEmpty) return;
    final bottleneck = await _bottleneckService.computeForProduct(
      factoryId,
      productId,
    );
    final effectiveCeiling = bottleneck.hasData ? bottleneck.achievable : null;

    final rows = [
      for (final day in days)
        {
          'factory_id': factoryId,
          'product_id': productId,
          'log_date': day.logDate.toIso8601String().substring(0, 10),
          'actual_output': day.actualOutput,
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
          'utilisation_percent':
              (effectiveCeiling != null && effectiveCeiling > 0)
              ? (day.actualOutput / effectiveCeiling) * 100
              : null,
          'downtime_hours': day.downtimeHours,
          'is_simulated': true,
        },
    ];
    await _client.from('daily_production').insert(rows);
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.production,
    );
  }

  Future<DailyProduction?> getForDate({
    required int factoryId,
    required int productId,
    required DateTime logDate,
  }) async {
    final row = await _client
        .from('daily_production')
        .select()
        .eq('factory_id', factoryId)
        .eq('product_id', productId)
        .eq('log_date', logDate.toIso8601String().substring(0, 10))
        .maybeSingle();
    return row == null ? null : DailyProduction.fromJson(row);
  }

  Future<List<DailyProduction>> getTrend(
    int factoryId, {
    required int productId,
    int days = 30,
  }) async {
    final since = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await _client
        .from('daily_production')
        .select()
        .eq('factory_id', factoryId)
        .eq('product_id', productId)
        .gte('log_date', since.toIso8601String().substring(0, 10))
        .order('log_date', ascending: true);
    return (rows as List)
        .map((row) => DailyProduction.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<DailyProduction>> getTrendAllProducts(
    int factoryId, {
    int days = 30,
  }) async {
    final since = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await _client
        .from('daily_production')
        .select()
        .eq('factory_id', factoryId)
        .gte('log_date', since.toIso8601String().substring(0, 10))
        .order('log_date', ascending: true);

    final byDate = <String, DailyProduction>{};
    for (final raw in rows as List) {
      final dp = DailyProduction.fromJson(raw as Map<String, dynamic>);
      final key = dp.logDate.toIso8601String().substring(0, 10);
      final prev = byDate[key];
      final ceiling = dp.effectiveCeiling == null && prev?.effectiveCeiling == null
          ? null
          : (prev?.effectiveCeiling ?? 0) + (dp.effectiveCeiling ?? 0);
      byDate[key] = DailyProduction(
        dailyId: prev?.dailyId ?? dp.dailyId,
        factoryId: factoryId,
        productId: 0,
        logDate: dp.logDate,
        actualOutput: (prev?.actualOutput ?? 0) + dp.actualOutput,
        effectiveCeiling: ceiling,
        downtimeHours: (prev?.downtimeHours ?? 0) + dp.downtimeHours,
        isSimulated: false,
      );
    }
    return byDate.values.toList()
      ..sort((a, b) => a.logDate.compareTo(b.logDate));
  }

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

    final dailyTotals = <DateTime, double>{};
    for (final row in rows as List) {
      final map = row as Map<String, dynamic>;
      final day = DateTime.parse(map['log_date'] as String);
      dailyTotals[day] =
          (dailyTotals[day] ?? 0) + (map['actual_output'] as num).toDouble();
    }

    final totals = <DateTime, double>{};
    final counts = <DateTime, int>{};
    for (final entry in dailyTotals.entries) {
      final month = DateTime(entry.key.year, entry.key.month);
      totals[month] = (totals[month] ?? 0) + entry.value;
      counts[month] = (counts[month] ?? 0) + 1;
    }
    return {
      for (final entry in totals.entries)
        entry.key: entry.value / counts[entry.key]!,
    };
  }
}
