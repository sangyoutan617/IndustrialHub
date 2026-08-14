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

  /// The authoritative capacity/bottleneck verdict — computed server-side
  /// by the compute_bottleneck() Postgres function, not re-derived from raw
  /// table reads here. The
  /// what-if simulator (simulator_screen.dart) is the one place that still
  /// does this math on the client: it's read-only and needs instant slider
  /// feedback, so local computation is the right call there. Everywhere
  /// else — dashboards, admin analytics, material alerts — reads this.
  Future<BottleneckResult> computeForFactory(int factoryId) async {
    final row = await _client
        .rpc('compute_bottleneck', params: {'p_factory_id': factoryId})
        .single();

    return BottleneckResult(
      hasData: row['has_data'] as bool,
      machineCapacity: (row['machine_capacity'] as num).toDouble(),
      manpowerCapacity: (row['manpower_capacity'] as num).toDouble(),
      bottleneckResource: row['bottleneck_resource'] as String,
      materialCeiling: (row['material_ceiling'] as num?)?.toDouble(),
      requiredPerDay: (row['required_per_day'] as num).toDouble(),
      achievable: (row['achievable'] as num).toDouble(),
      canMeetDemand: row['can_meet_demand'] as bool,
      limiter: row['limiter'] as String?,
      shortfall: (row['shortfall'] as num?)?.toDouble(),
    );
  }
}
