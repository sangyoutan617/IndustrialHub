import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/raw_material.dart';
import 'data_event_service.dart';
import 'supply_exceptions.dart';

class MaterialService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<RawMaterial>> getMaterials(int factoryId) async {
    final rows = await _client
        .from('raw_materials')
        .select()
        .eq('factory_id', factoryId)
        .order('material_name', ascending: true);
    return (rows as List)
        .map((row) => RawMaterial.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<RawMaterial> createMaterial(RawMaterial material) async {
    final row = await _client
        .from('raw_materials')
        .insert(material.toInsertJson(material.factoryId))
        .select()
        .single();
    final result = RawMaterial.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: material.factoryId,
      source: DataChangeSource.supply,
    );
    return result;
  }

  Future<RawMaterial> updateMaterial(
    int materialId,
    RawMaterial material,
  ) async {
    final row = await _client
        .from('raw_materials')
        .update({
          ...material.toInsertJson(material.factoryId),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('material_id', materialId)
        .select()
        .single();
    final result = RawMaterial.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: material.factoryId,
      source: DataChangeSource.supply,
    );
    return result;
  }

  Future<void> deleteMaterial(int materialId, {int? factoryId}) async {
    final linkedSuppliers = await _client
        .from('suppliers')
        .select('supplier_id')
        .eq('material_id', materialId)
        .limit(1);
    if ((linkedSuppliers as List).isNotEmpty) {
      throw const SupplyInUseException(
        'This material still has suppliers linked to it — remove those '
        'suppliers first.',
      );
    }
    final linkedOrders = await _client
        .from('purchase_orders')
        .select('po_id')
        .eq('material_id', materialId)
        .limit(1);
    if ((linkedOrders as List).isNotEmpty) {
      throw const SupplyInUseException(
        'This material has purchase order history — it cannot be removed.',
      );
    }
    try {
      await _client
          .from('raw_materials')
          .delete()
          .eq('material_id', materialId);
      if (factoryId != null) {
        DataEventService.instance.notifyChanged(
          factoryId: factoryId,
          source: DataChangeSource.supply,
        );
      }
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const SupplyInUseException(
          'This material is now linked to a supplier or purchase order — '
          'it cannot be removed.',
        );
      }
      rethrow;
    }
  }
}
