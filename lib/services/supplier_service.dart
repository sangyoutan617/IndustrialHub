import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier.dart';
import 'supply_exceptions.dart';

class SupplierService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Supplier>> getSuppliersForMaterials(List<int> materialIds) async {
    if (materialIds.isEmpty) return [];
    final rows = await _client
        .from('suppliers')
        .select()
        .inFilter('material_id', materialIds)
        .order('supplier_name', ascending: true);
    return (rows as List)
        .map((row) => Supplier.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Supplier> createSupplier(
    Supplier supplier, {
    bool isSimulated = false,
  }) async {
    final row = await _client
        .from('suppliers')
        .insert({
          ...supplier.toInsertJson(),
          if (isSimulated) 'is_simulated': true,
        })
        .select()
        .single();
    return Supplier.fromJson(row);
  }

  Future<Supplier> updateSupplier(int supplierId, Supplier supplier) async {
    final row = await _client
        .from('suppliers')
        .update({
          ...supplier.toInsertJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('supplier_id', supplierId)
        .select()
        .single();
    return Supplier.fromJson(row);
  }

  /// Single-field patch for the quick-rate action, so updating a
  /// supplier's reliability doesn't require reopening the full form.
  Future<Supplier> updateRating(int supplierId, double rating) async {
    final row = await _client
        .from('suppliers')
        .update({
          'reliability_rating': rating,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('supplier_id', supplierId)
        .select()
        .single();
    return Supplier.fromJson(row);
  }

  Future<void> deleteSupplier(int supplierId) async {
    // Blocks on ANY purchase order history, not just open ones — matching
    // MaterialService.deleteMaterial's rule. A supplier with only
    // Delivered/Cancelled orders looked safe to remove, but deleting it
    // orphans those orders (they'd render "Unknown supplier") and erases
    // the delivery history that on-time-rate and supplier comparison
    // depend on.
    final linkedOrders = await _client
        .from('purchase_orders')
        .select('po_id')
        .eq('supplier_id', supplierId)
        .limit(1);
    if ((linkedOrders as List).isNotEmpty) {
      throw const SupplyInUseException(
        'This supplier has purchase order history — it cannot be removed. '
        'Cancel any open orders first; delivered orders keep this supplier '
        'in use permanently.',
      );
    }
    // Friendly fast path above; the database's foreign-key constraint is
    // the real guarantee against an order inserted in between.
    try {
      await _client.from('suppliers').delete().eq('supplier_id', supplierId);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const SupplyInUseException(
          'This supplier now has purchase order history — it cannot be '
          'removed.',
        );
      }
      rethrow;
    }
  }
}
