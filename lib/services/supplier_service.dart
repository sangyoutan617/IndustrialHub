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
    final openOrders = await _client
        .from('purchase_orders')
        .select('po_id')
        .eq('supplier_id', supplierId)
        .not('status', 'in', '(Delivered,Cancelled)')
        .limit(1);
    if ((openOrders as List).isNotEmpty) {
      throw const SupplyInUseException(
        'This supplier has an open purchase order — cancel or complete it '
        'before removing the supplier.',
      );
    }
    await _client.from('suppliers').delete().eq('supplier_id', supplierId);
  }
}
