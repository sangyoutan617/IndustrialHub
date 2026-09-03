import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/factory.dart';
import 'bottleneck_service.dart';
import 'factory_service.dart';
import 'product_service.dart';

class FactoryStat {
  final Factory factory;

  final List<ProductBottleneck> products;

  const FactoryStat({required this.factory, required this.products});

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

class CrossFactoryStats {
  final List<FactoryStat> factories;

  const CrossFactoryStats({required this.factories});

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
  final ProductService _productService = ProductService();

  Future<bool> isAdmin(String userId) async {
    final row = await _client
        .from('admins')
        .select('admin_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  Future<Map<String, bool>> getUserBanStatuses() async {
    final rows = await _client.rpc('admin_list_user_ban_status');
    return {
      for (final row in rows as List)
        (row as Map<String, dynamic>)['user_id'] as String:
            row['is_banned'] as bool,
    };
  }

  Future<void> setUserBanned(String userId, bool banned) async {
    await _client.rpc(
      'admin_set_user_banned',
      params: {'p_user_id': userId, 'p_banned': banned},
    );
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

      stats.add(FactoryStat(factory: factory, products: productBottlenecks));
    }

    return CrossFactoryStats(factories: stats);
  }
}
