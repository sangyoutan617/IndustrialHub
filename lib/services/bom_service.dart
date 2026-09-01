import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bom_entry.dart';
import '../models/product.dart';
import 'data_event_service.dart';

class BomService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<BomEntry>> getBom(int productId) async {
    final rows = await _client
        .from('product_materials')
        .select()
        .eq('product_id', productId);
    return (rows as List)
        .map((row) => BomEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<BomEntry>> getAllForFactory(int factoryId) async {
    final rows = await _client
        .from('product_materials')
        .select('*, products!inner(factory_id)')
        .eq('products.factory_id', factoryId);
    return (rows as List)
        .map((row) => BomEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<Product>> getProductsUsing(int materialId) async {
    final rows = await _client
        .from('product_materials')
        .select('products(*)')
        .eq('material_id', materialId);
    return (rows as List)
        .map(
          (row) =>
              Product.fromJson((row as Map)['products'] as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> upsertEntry(BomEntry entry, {required int factoryId}) async {
    await _client
        .from('product_materials')
        .upsert(entry.toInsertJson(), onConflict: 'product_id,material_id');
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.supply,
    );
  }

  Future<void> deleteEntry({
    required int productId,
    required int materialId,
    required int factoryId,
  }) async {
    await _client
        .from('product_materials')
        .delete()
        .eq('product_id', productId)
        .eq('material_id', materialId);
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.supply,
    );
  }
}
