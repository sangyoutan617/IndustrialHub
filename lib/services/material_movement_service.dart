import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bom_entry.dart';
import '../models/raw_material.dart';
import '../models/raw_material_movement.dart';
import 'data_event_service.dart';
import 'mrp_service.dart';

class MaterialMovementService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> recordBulkMovements({
    required int factoryId,
    required List<
      ({
        int materialId,
        String movementType,
        double quantity,
        DateTime movementDate,
        String? note,
      })
    >
    movements,
    required Map<int, double> finalStockByMaterialId,
  }) async {
    if (movements.isNotEmpty) {
      await _client.from('raw_material_movements').insert([
        for (final m in movements)
          {
            'material_id': m.materialId,
            'factory_id': factoryId,
            'movement_type': m.movementType,
            'quantity': m.quantity,
            'movement_date': m.movementDate.toIso8601String().substring(0, 10),
            'note': m.note,
            'is_simulated': true,
          },
      ]);
    }
    for (final entry in finalStockByMaterialId.entries) {
      await _client
          .from('raw_materials')
          .update({
            'current_stock': entry.value,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('material_id', entry.key);
    }
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.supply,
    );
  }

  Future<List<RawMaterialMovement>> getMovements(int materialId) async {
    final rows = await _client
        .from('raw_material_movements')
        .select()
        .eq('material_id', materialId)
        .order('movement_date', ascending: false)
        .order('movement_id', ascending: false);
    return (rows as List)
        .map((row) => RawMaterialMovement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordMovement({
    required int materialId,
    required int factoryId,
    required String movementType,
    required double quantity,
    required DateTime movementDate,
    String? note,
    bool isSimulated = false,
  }) async {
    final current = await _client
        .from('raw_materials')
        .select('current_stock')
        .eq('material_id', materialId)
        .single();
    final currentStock = (current['current_stock'] as num).toDouble();

    final delta = switch (movementType) {
      RawMaterialMovementType.consumption => -quantity.abs(),
      RawMaterialMovementType.receipt => quantity.abs(),
      _ => quantity,
    };
    final newStock = currentStock + delta;
    if (newStock < 0) {
      throw Exception('This movement would take stock below zero.');
    }

    await _client.from('raw_material_movements').insert({
      'material_id': materialId,
      'factory_id': factoryId,
      'movement_type': movementType,
      'quantity': quantity,
      'movement_date': movementDate.toIso8601String().substring(0, 10),
      'note': note,
      if (isSimulated) 'is_simulated': true,
    });

    await _client
        .from('raw_materials')
        .update({
          'current_stock': newStock,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('material_id', materialId);

    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.supply,
    );
  }

  Future<List<int>> recordProductionConsumption({
    required int factoryId,
    required List<RawMaterial> materials,
    required List<BomEntry> bom,
    required int unitsDelta,
    required DateTime date,
  }) async {
    if (unitsDelta == 0) return const [];
    final isReturn = unitsDelta < 0;
    final consumption = MrpService.computeProductionConsumption(
      bom,
      unitsDelta.abs(),
    );
    final byId = {for (final m in materials) m.materialId: m};
    final skipped = <int>[];
    for (final entry in consumption.entries) {
      final material = byId[entry.key];
      if (material == null) {
        skipped.add(entry.key);
        continue;
      }
      if (!isReturn && entry.value > material.currentStock) {
        skipped.add(entry.key);
        continue;
      }
      await recordMovement(
        materialId: entry.key,
        factoryId: factoryId,
        movementType: isReturn
            ? RawMaterialMovementType.adjustment
            : RawMaterialMovementType.consumption,
        quantity: entry.value,
        movementDate: date,
        note: isReturn
            ? 'Correction: production reduced by ${unitsDelta.abs()} units'
            : 'Production of $unitsDelta units',
      );
    }
    return skipped;
  }
}
