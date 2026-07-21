import 'package:supabase_flutter/supabase_flutter.dart';

class BottleneckResult {
  final bool hasData;
  final double machineCapacity;
  final double manpowerCapacity;
  final String bottleneckResource;
  final double? materialCeiling;
  final double requiredPerDay;
  final double achievable;
  final bool canMeetDemand;
  final String? limiter;
  final double? shortfall;

  const BottleneckResult({
    required this.hasData,
    required this.machineCapacity,
    required this.manpowerCapacity,
    required this.bottleneckResource,
    required this.materialCeiling,
    required this.requiredPerDay,
    required this.achievable,
    required this.canMeetDemand,
    required this.limiter,
    required this.shortfall,
  });

  factory BottleneckResult.empty() {
    return const BottleneckResult(
      hasData: false,
      machineCapacity: 0,
      manpowerCapacity: 0,
      bottleneckResource: 'MACHINE',
      materialCeiling: null,
      requiredPerDay: 0,
      achievable: 0,
      canMeetDemand: true,
      limiter: null,
      shortfall: null,
    );
  }
}

class BottleneckService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<BottleneckResult> computeForFactory(int factoryId) async {
    final machines = await _client
        .from('machines')
        .select(
          'rated_output_per_hour, operating_hours_per_day, uptime_percent',
        )
        .eq('factory_id', factoryId)
        .eq('status', 'Active');

    final manpower = await _client
        .from('manpower')
        .select('worker_count, shift_hours, output_per_worker_hour')
        .eq('factory_id', factoryId);

    final materials = await _client
        .from('raw_materials')
        .select('current_stock, consumption_per_unit')
        .eq('factory_id', factoryId);

    final demand = await _client
        .from('demand_forecast')
        .select('required_per_day')
        .eq('factory_id', factoryId);

    if ((machines as List).isEmpty &&
        (manpower as List).isEmpty &&
        (materials as List).isEmpty &&
        (demand as List).isEmpty) {
      return BottleneckResult.empty();
    }

    final machineCapacity = machines.fold<double>(0, (sum, row) {
      final rated = (row['rated_output_per_hour'] as num).toDouble();
      final hours = (row['operating_hours_per_day'] as num).toDouble();
      final uptime = (row['uptime_percent'] as num).toDouble();
      return sum + rated * hours * (uptime / 100);
    });

    final manpowerCapacity = manpower.fold<double>(0, (sum, row) {
      final workers = (row['worker_count'] as num).toDouble();
      final hours = (row['shift_hours'] as num).toDouble();
      final perHour = (row['output_per_worker_hour'] as num).toDouble();
      return sum + workers * hours * perHour;
    });

    final productionCeiling = machineCapacity < manpowerCapacity
        ? machineCapacity
        : manpowerCapacity;
    final bottleneckResource = machineCapacity < manpowerCapacity
        ? 'MACHINE'
        : 'MANPOWER';

    double? materialCeiling;
    for (final row in materials) {
      final consumptionPerUnit = (row['consumption_per_unit'] as num)
          .toDouble();
      if (consumptionPerUnit <= 0) continue;
      final stock = (row['current_stock'] as num).toDouble();
      final ceiling = stock / consumptionPerUnit;
      if (materialCeiling == null || ceiling < materialCeiling) {
        materialCeiling = ceiling;
      }
    }

    final requiredPerDay = demand.fold<double>(
      0,
      (sum, row) => sum + (row['required_per_day'] as num).toDouble(),
    );

    final achievable = materialCeiling == null
        ? productionCeiling
        : (productionCeiling < materialCeiling
              ? productionCeiling
              : materialCeiling);

    final canMeetDemand = achievable >= requiredPerDay;
    String? limiter;
    double? shortfall;
    if (!canMeetDemand) {
      shortfall = requiredPerDay - achievable;
      limiter = (materialCeiling != null && materialCeiling < productionCeiling)
          ? 'RAW MATERIAL'
          : bottleneckResource;
    }

    return BottleneckResult(
      hasData: true,
      machineCapacity: machineCapacity,
      manpowerCapacity: manpowerCapacity,
      bottleneckResource: bottleneckResource,
      materialCeiling: materialCeiling,
      requiredPerDay: requiredPerDay,
      achievable: achievable,
      canMeetDemand: canMeetDemand,
      limiter: limiter,
      shortfall: shortfall,
    );
  }
}
