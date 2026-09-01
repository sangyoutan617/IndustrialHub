import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

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

class ProductBottleneck {
  final Product product;
  final BottleneckResult bottleneck;

  const ProductBottleneck({required this.product, required this.bottleneck});
}

class BottleneckService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<BottleneckResult> computeForFactory(int factoryId) async {
    final row = await _client
        .rpc('compute_bottleneck', params: {'p_factory_id': factoryId})
        .single();
    return _fromRow(row);
  }

  Future<BottleneckResult> computeForProduct(
    int factoryId,
    int productId,
  ) async {
    final row = await _client
        .rpc(
          'compute_bottleneck',
          params: {'p_factory_id': factoryId, 'p_product_id': productId},
        )
        .single();
    return _fromRow(row);
  }

  BottleneckResult _fromRow(Map<String, dynamic> row) {
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
