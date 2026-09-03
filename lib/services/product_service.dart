import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'data_event_service.dart';
import 'supply_exceptions.dart';

class ProductService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Product>> getProducts(
    int factoryId, {
    bool includeArchived = false,
  }) async {
    var query = _client.from('products').select().eq('factory_id', factoryId);
    if (!includeArchived) {
      query = query.eq('status', 'active');
    }
    final rows = await query
        .order('is_general', ascending: true)
        .order('product_name', ascending: true);
    return (rows as List)
        .map((row) => Product.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Product> createProduct(Product product) async {
    final row = await _client
        .from('products')
        .insert(product.toInsertJson(product.factoryId))
        .select()
        .single();
    final result = Product.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: product.factoryId,
      source: DataChangeSource.capacity,
    );
    return result;
  }

  Future<Product> renameProduct(int productId, String productName) async {
    final row = await _client
        .from('products')
        .update({'product_name': productName})
        .eq('product_id', productId)
        .select()
        .single();
    final result = Product.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: result.factoryId,
      source: DataChangeSource.capacity,
    );
    return result;
  }

  Future<Product> updateProduct(int productId, Product product) async {
    final row = await _client
        .from('products')
        .update(product.toInsertJson(product.factoryId))
        .eq('product_id', productId)
        .select()
        .single();
    final result = Product.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: product.factoryId,
      source: DataChangeSource.capacity,
    );
    return result;
  }

  Future<void> archiveProduct(int productId, {required int factoryId}) async {
    final activeDemand = await _client
        .from('demand_forecast')
        .select('demand_id')
        .eq('product_id', productId)
        .gt('required_per_day', 0)
        .limit(1);
    if ((activeDemand as List).isNotEmpty) {
      throw const SupplyInUseException(
        'Cannot archive product with active demand. Please complete or '
        'remove the active demand target first.',
      );
    }
    await _client
        .from('products')
        .update({'status': 'archived'})
        .eq('product_id', productId);
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.capacity,
    );
  }

  Future<void> reactivateProduct(
    int productId, {
    required int factoryId,
  }) async {
    await _client
        .from('products')
        .update({'status': 'active'})
        .eq('product_id', productId);
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.capacity,
    );
  }

  Future<void> deleteProduct(int productId, {required int factoryId}) async {
    final checks = <(String, String, String)>[
      ('machines', 'machine_id', 'This product still has machines assigned to it — reassign them first.'),
      ('manpower', 'manpower_id', 'This product still has manpower shifts assigned to it — reassign them first.'),
      ('product_materials', 'material_id', 'This product still has material requirements set — remove them first.'),
      ('demand_forecast', 'demand_id', 'This product still has a demand forecast set — remove it first.'),
      ('daily_production', 'daily_id', 'This product has production history — it cannot be removed.'),
    ];
    for (final (table, idColumn, message) in checks) {
      final linked = await _client
          .from(table)
          .select(idColumn)
          .eq('product_id', productId)
          .limit(1);
      if ((linked as List).isNotEmpty) {
        throw SupplyInUseException(message);
      }
    }
    final stockRow = await _client
        .from('finished_stock')
        .select('stock_id, current_quantity')
        .eq('product_id', productId)
        .maybeSingle();
    if (stockRow != null) {
      final stockId = stockRow['stock_id'] as int;
      final quantity = stockRow['current_quantity'] as int;
      final movements = await _client
          .from('stock_movements')
          .select('movement_id')
          .eq('stock_id', stockId)
          .limit(1);
      if (quantity != 0 || (movements as List).isNotEmpty) {
        throw const SupplyInUseException(
          'This product still has finished-goods stock tracked — remove it first.',
        );
      }
      await _client.from('finished_stock').delete().eq('stock_id', stockId);
    }
    try {
      await _client.from('products').delete().eq('product_id', productId);
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.capacity,
      );
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const SupplyInUseException(
          'This product is now referenced elsewhere — it cannot be removed.',
        );
      }
      rethrow;
    }
  }
}
