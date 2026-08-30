import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'data_event_service.dart';
import 'supply_exceptions.dart';

class ProductService {
  final SupabaseClient _client = Supabase.instance.client;

  /// General sorts last — it's the migration catch-all, not something a
  /// user actively picks first when choosing what to assign a machine to.
  Future<List<Product>> getProducts(int factoryId) async {
    final rows = await _client
        .from('products')
        .select()
        .eq('factory_id', factoryId)
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

  /// Renames a product without touching its other fields. A targeted
  /// update rather than [updateProduct]'s full-object overwrite — a caller
  /// that only has a name in hand (e.g. a rename-only flow on another
  /// module's screen, which doesn't know this product's unit) would
  /// otherwise silently reset unit to its default via toInsertJson.
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

  /// Deletes a product. Refuses (with a friendly message) if anything still
  /// references it — a machine/shift/material-rate/finished-stock/demand
  /// row left pointing at a deleted product would either violate the FK
  /// outright or, worse, silently orphan data, so this is checked up front
  /// the same way [MaterialService.deleteMaterial] guards its own deletes.
  /// The database's `ON DELETE RESTRICT` is the real backstop if a row is
  /// inserted in the race between this check and the delete.
  Future<void> deleteProduct(int productId, {required int factoryId}) async {
    final checks = <(String, String, String)>[
      ('machines', 'machine_id', 'This product still has machines assigned to it — reassign them first.'),
      ('manpower', 'manpower_id', 'This product still has manpower shifts assigned to it — reassign them first.'),
      ('product_materials', 'material_id', 'This product still has material requirements set — remove them first.'),
      ('finished_stock', 'stock_id', 'This product still has finished-goods stock tracked — remove it first.'),
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
