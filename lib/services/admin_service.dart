import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/factory.dart';
import '../models/productivity_benchmark.dart';
import 'bottleneck_service.dart';
import 'capacity_service.dart';
import 'factory_service.dart';

class FactoryStat {
  final Factory factory;
  final BottleneckResult bottleneck;
  final double? outputPerWorker;
  final String? msicCategory;

  const FactoryStat({
    required this.factory,
    required this.bottleneck,
    required this.outputPerWorker,
    required this.msicCategory,
  });
}

class DivisionIpiReading {
  final String division;
  final String? divisionName;
  final double productionIndex;

  const DivisionIpiReading({
    required this.division,
    required this.divisionName,
    required this.productionIndex,
  });
}

class CategoryProductivity {
  final String category;
  final ProductivityBenchmark benchmark;
  final double avgOutputPerWorker;
  final int factoryCount;
  final int belowPeerMedianCount;

  const CategoryProductivity({
    required this.category,
    required this.benchmark,
    required this.avgOutputPerWorker,
    required this.factoryCount,
    required this.belowPeerMedianCount,
  });
}

class CrossFactoryStats {
  final List<FactoryStat> factories;
  final double totalAchievable;
  final double totalDemand;
  final int factoriesBelowDemand;
  final List<DivisionIpiReading> ipiReadings;
  final List<CategoryProductivity> productivity;

  const CrossFactoryStats({
    required this.factories,
    required this.totalAchievable,
    required this.totalDemand,
    required this.factoriesBelowDemand,
    required this.ipiReadings,
    required this.productivity,
  });
}

class AdminService {
  final SupabaseClient _client = Supabase.instance.client;
  final FactoryService _factoryService = FactoryService();
  final BottleneckService _bottleneckService = BottleneckService();
  final CapacityService _capacityService = CapacityService();

  Future<bool> isAdmin(String userId) async {
    final row = await _client
        .from('admins')
        .select('admin_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  /// Per-factory bottleneck stats reuse [BottleneckService] and
  /// [CapacityService] rather than re-deriving the capacity math here.
  Future<CrossFactoryStats> crossFactoryStats() async {
    final factories = await _factoryService.getFactories();

    final stats = <FactoryStat>[];
    for (final factory in factories) {
      final bottleneck = await _bottleneckService.computeForFactory(
        factory.factoryId,
      );

      double? outputPerWorker;
      String? category;
      final msicCode = factory.msicCode;
      if (msicCode != null && msicCode.isNotEmpty) {
        final snapshot = await _capacityService.getSnapshot(factory.factoryId);
        outputPerWorker = _capacityService.outputPerWorker(snapshot);
        final msic = await _capacityService.getMsicByCode(msicCode);
        category = msic?.category;
      }

      stats.add(
        FactoryStat(
          factory: factory,
          bottleneck: bottleneck,
          outputPerWorker: outputPerWorker,
          msicCategory: category,
        ),
      );
    }

    final withData = stats.where((s) => s.bottleneck.hasData);
    final totalAchievable = withData.fold<double>(
      0,
      (sum, s) => sum + s.bottleneck.achievable,
    );
    final totalDemand = withData.fold<double>(
      0,
      (sum, s) => sum + s.bottleneck.requiredPerDay,
    );
    final factoriesBelowDemand = withData
        .where((s) => !s.bottleneck.canMeetDemand)
        .length;

    final divisions = <String>{
      for (final f in factories)
        if (f.msicCode != null && f.msicCode!.isNotEmpty)
          f.msicCode!.length >= 2 ? f.msicCode!.substring(0, 2) : f.msicCode!,
    };
    final ipiReadings = <DivisionIpiReading>[];
    for (final division in divisions) {
      final trend = await _capacityService.getIpiTrend(division, months: 1);
      if (trend.isNotEmpty) {
        ipiReadings.add(
          DivisionIpiReading(
            division: division,
            divisionName: trend.last.divisionName,
            productionIndex: trend.last.productionIndex,
          ),
        );
      }
    }

    // DOSM's productivity benchmark is RM value-added/worker/year — a
    // different unit to this app's physical units/day/worker, and there is
    // no selling price in the schema to convert between them (see
    // benchmark_screen's own disclaimer for the same limitation). So
    // "below the productivity benchmark" is computed as below the peer
    // median output/worker among factories that share the same MSIC
    // category, not against the DOSM RM figure directly. The DOSM figure is
    // still shown alongside, for context only.
    final categories = <String>{
      for (final s in stats)
        if (s.msicCategory != null) s.msicCategory!,
    };
    final productivity = <CategoryProductivity>[];
    for (final category in categories) {
      final benchmark = await _capacityService.getProductivityBenchmark(
        category,
      );
      if (benchmark == null) continue;

      final peers =
          stats
              .where(
                (s) => s.msicCategory == category && s.outputPerWorker != null,
              )
              .map((s) => s.outputPerWorker!)
              .toList()
            ..sort();
      if (peers.isEmpty) continue;

      final median = peers.length.isOdd
          ? peers[peers.length ~/ 2]
          : (peers[peers.length ~/ 2 - 1] + peers[peers.length ~/ 2]) / 2;
      final avg = peers.fold<double>(0, (sum, v) => sum + v) / peers.length;
      final belowMedian = peers.where((v) => v < median).length;

      productivity.add(
        CategoryProductivity(
          category: category,
          benchmark: benchmark,
          avgOutputPerWorker: avg,
          factoryCount: peers.length,
          belowPeerMedianCount: belowMedian,
        ),
      );
    }

    return CrossFactoryStats(
      factories: stats,
      totalAchievable: totalAchievable,
      totalDemand: totalDemand,
      factoriesBelowDemand: factoriesBelowDemand,
      ipiReadings: ipiReadings,
      productivity: productivity,
    );
  }
}
