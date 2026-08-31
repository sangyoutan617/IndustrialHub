import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/daily_production.dart';
import 'bottleneck_service.dart';
import 'data_event_service.dart';

class DailyProductionService {
  final SupabaseClient _client = Supabase.instance.client;
  final BottleneckService _bottleneckService = BottleneckService();

  /// Logs (or re-logs) one product's production for one day. Reuses
  /// [BottleneckService.computeForProduct] for the ceiling/bottleneck math
  /// rather than re-deriving it — scoped to [productId] rather than the
  /// whole factory, since machines/manpower/materials are now product-owned
  /// and a factory-wide figure would blend unrelated products together.
  /// Upserts on (factory_id, product_id, log_date) so re-logging the same
  /// product on the same day updates the existing row instead of creating a
  /// duplicate; a different product on the same day is its own row.
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

  /// Bulk-writes many days of production in one round trip, reusing a single
  /// bottleneck snapshot for all of them instead of the one-`compute_bottleneck`-
  /// call-per-day [logProduction] makes for a single live entry. Only valid
  /// when capacity genuinely doesn't change across the whole batch (e.g.
  /// backfilling demo history immediately after machines/manpower were
  /// seeded, before anything about them could have changed) — a real
  /// day-by-day log always goes through [logProduction] instead, since a
  /// machine going down partway through *should* change later days' ceiling.
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

  /// The row already logged for one product on one day, if any — used to
  /// find the previously logged output before overwriting it, so a caller
  /// can deduct/return only the *change* in material consumption rather
  /// than the whole new total again.
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

  /// One product's trend — the chart and downtime summary on
  /// production_trend_screen.dart are both scoped to a single product at a
  /// time, since a factory-wide sum would mix output figures across
  /// products that may not even share a unit.
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

  /// Every product's trend combined — the production_trend_screen's "All
  /// products" view. Rows are collapsed to one synthetic record per
  /// `log_date`, summing `actual_output`, `effective_ceiling` (products
  /// without a ceiling contribute 0; the sum is null only when *no* product
  /// that day had one) and `downtime_hours`. Mixed product units are added
  /// regardless — the caller opted into a combined figure. `productId` on the
  /// returned records is 0 (not a real product).
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

  /// Average *factory-wide* output per logged day, grouped by calendar
  /// month — feeds the sector (IPI) benchmark, which compares total factory
  /// output, not any one product. A factory can now log several rows per
  /// day (one per product), so rows are first collapsed into one total per
  /// calendar day before averaging within the month; averaging naively over
  /// (day, product) rows would dilute the average by however many products
  /// were logged that day instead of by how many days were logged.
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
