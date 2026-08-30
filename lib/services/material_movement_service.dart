import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bom_entry.dart';
import '../models/raw_material.dart';
import '../models/raw_material_movement.dart';
import 'data_event_service.dart';
import 'mrp_service.dart';

/// Writes the raw-material stock ledger and keeps `raw_materials.current_stock`
/// in step. The raw-material equivalent of [StockService.recordMovement] for
/// finished goods — the two ledgers are deliberately separate.
class MaterialMovementService {
  final SupabaseClient _client = Supabase.instance.client;

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

  /// Records one ledger entry and applies its signed delta to the material's
  /// current stock. `consumption` subtracts, `receipt` adds, `adjustment` adds
  /// the signed [quantity] as given (pass a negative number to remove stock).
  /// Throws before writing anything if the result would go below zero, so a
  /// mistyped consumption can't push stock negative.
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

  /// Deducts the raw material one product's production run consumed
  /// ([MrpService.computeProductionConsumption], using that product's own
  /// [bom]). Any material without enough stock is skipped (its id returned)
  /// rather than driving stock negative, so the caller can warn without the
  /// whole run failing. Never throws for insufficient stock.
  Future<List<int>> recordProductionConsumption({
    required int factoryId,
    required List<RawMaterial> materials,
    required List<BomEntry> bom,
    required int unitsProduced,
    required DateTime date,
  }) async {
    final consumption = MrpService.computeProductionConsumption(
      bom,
      unitsProduced,
    );
    final byId = {for (final m in materials) m.materialId: m};
    final skipped = <int>[];
    for (final entry in consumption.entries) {
      final material = byId[entry.key];
      if (material == null || entry.value > material.currentStock) {
        skipped.add(entry.key);
        continue;
      }
      await recordMovement(
        materialId: entry.key,
        factoryId: factoryId,
        movementType: RawMaterialMovementType.consumption,
        quantity: entry.value,
        movementDate: date,
        note: 'Production of $unitsProduced units',
      );
    }
    return skipped;
  }
}
