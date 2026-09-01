import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/factory.dart';
import '../models/productivity_benchmark.dart';
import 'bottleneck_service.dart';
import 'capacity_service.dart';
import 'factory_service.dart';
import 'product_service.dart';

class FactoryStat {
  final Factory factory;

  final List<ProductBottleneck> products;
  final double? outputPerWorker;
  final String? msicCategory;

  const FactoryStat({
    required this.factory,
    required this.products,
    required this.outputPerWorker,
    required this.msicCategory,
  });

  Iterable<ProductBottleneck> get _withData =>
      products.where((p) => p.bottleneck.hasData);

  int get productsWithData => _withData.length;

  int get productsMeetingDemand =>
      _withData.where((p) => p.bottleneck.canMeetDemand).length;

  int get productsShort => productsWithData - productsMeetingDemand;

  String? get dominantBottleneckResource {
    final short = _withData.where((p) => !p.bottleneck.canMeetDemand);
    if (short.isEmpty) return null;
    final counts = <String, int>{};
    for (final p in short) {
      final key = p.bottleneck.limiter ?? p.bottleneck.bottleneckResource;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
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
  final List<DivisionIpiReading> ipiReadings;
  final List<CategoryProductivity> productivity;

  const CrossFactoryStats({
    required this.factories,
    required this.ipiReadings,
    required this.productivity,
  });

  int get totalProductsWithData =>
      factories.fold(0, (sum, f) => sum + f.productsWithData);

  int get totalProductsMeetingDemand =>
      factories.fold(0, (sum, f) => sum + f.productsMeetingDemand);

  int get totalProductsShort =>
      totalProductsWithData - totalProductsMeetingDemand;

  int get factoriesAtRisk =>
      factories.where((f) => f.productsShort > 0).length;
}

class AdminService {
  final SupabaseClient _client = Supabase.instance.client;
  final FactoryService _factoryService = FactoryService();
  final BottleneckService _bottleneckService = BottleneckService();
  final CapacityService _capacityService = CapacityService();
  final ProductService _productService = ProductService();

  Future<bool> isAdmin(String userId) async {
    final row = await _client
        .from('admins')
        .select('admin_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  Future<CrossFactoryStats> crossFactoryStats() async {
    final factories = await _factoryService.getFactories();

    final stats = <FactoryStat>[];
    for (final factory in factories) {
      final products = await _productService.getProducts(factory.factoryId);
      final bottlenecks = await Future.wait(
        products.map(
          (p) => _bottleneckService.computeForProduct(
            factory.factoryId,
            p.productId,
          ),
        ),
      );
      final productBottlenecks = [
        for (var i = 0; i < products.length; i++)
          ProductBottleneck(product: products[i], bottleneck: bottlenecks[i]),
      ];

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
          products: productBottlenecks,
          outputPerWorker: outputPerWorker,
          msicCategory: category,
        ),
      );
    }

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
      ipiReadings: ipiReadings,
      productivity: productivity,
    );
  }
}
