class RawMaterial {
  final int materialId;
  final int factoryId;
  final String materialName;
  final double currentStock;
  final String unit;

  /// The old single-rate-per-material consumption assumption from before
  /// multi-product support — "how much of this material one produced unit
  /// uses," with no notion of *which* product. Superseded by the
  /// product_materials bill-of-materials (see BomService); no longer
  /// editable from the material form. Kept on the model only until nothing
  /// reads it and the column is dropped.
  final double consumptionPerUnit;
  final int safetyStockDays;

  /// Cost of one [unit] of this material on hand, in the factory's currency
  /// (RM). Null when no cost has been recorded — older rows predate cost
  /// tracking, so callers must treat it as unknown rather than zero.
  final double? unitCost;

  const RawMaterial({
    required this.materialId,
    required this.factoryId,
    required this.materialName,
    required this.currentStock,
    required this.unit,
    this.consumptionPerUnit = 0,
    this.safetyStockDays = 3,
    this.unitCost,
  });

  factory RawMaterial.fromJson(Map<String, dynamic> json) {
    return RawMaterial(
      materialId: json['material_id'] as int,
      factoryId: json['factory_id'] as int,
      materialName: json['material_name'] as String,
      currentStock: (json['current_stock'] as num).toDouble(),
      unit: json['unit'] as String? ?? 'kg',
      consumptionPerUnit: (json['consumption_per_unit'] as num).toDouble(),
      // Falls back to 3 when the column hasn't been migrated yet, so the
      // app keeps working against an older database schema.
      safetyStockDays: (json['safety_stock_days'] as num?)?.toInt() ?? 3,
      // Nullable and absent on an un-migrated database — stays null rather
      // than defaulting to a misleading zero cost.
      unitCost: (json['unit_cost'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'material_name': materialName,
      'current_stock': currentStock,
      'unit': unit,
      'consumption_per_unit': consumptionPerUnit,
      'safety_stock_days': safetyStockDays,
      'unit_cost': unitCost,
    };
  }
}
