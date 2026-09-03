import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier.dart';
import 'data_event_service.dart';
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
    int? factoryId,
  }) async {
    final row = await _client
        .from('suppliers')
        .insert({
          ...supplier.toInsertJson(),
          if (isSimulated) 'is_simulated': true,
        })
        .select()
        .single();
    final result = Supplier.fromJson(row);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.supply,
      );
    }
    return result;
  }

  Future<Supplier> updateSupplier(
    int supplierId,
    Supplier supplier, {
    int? factoryId,
  }) async {
    final row = await _client
        .from('suppliers')
        .update({
          ...supplier.toInsertJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('supplier_id', supplierId)
        .select()
        .single();
    final result = Supplier.fromJson(row);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.supply,
      );
    }
    return result;
  }

  Future<Supplier> updateRating(
    int supplierId,
    double rating, {
    int? factoryId,
  }) async {
    final row = await _client
        .from('suppliers')
        .update({
          'reliability_rating': rating,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('supplier_id', supplierId)
        .select()
        .single();
    final result = Supplier.fromJson(row);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.supply,
      );
    }
    return result;
  }

  Future<void> deleteSupplier(int supplierId, {int? factoryId}) async {
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
    try {
      await _client.from('suppliers').delete().eq('supplier_id', supplierId);
      if (factoryId != null) {
        DataEventService.instance.notifyChanged(
          factoryId: factoryId,
          source: DataChangeSource.supply,
        );
      }
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
