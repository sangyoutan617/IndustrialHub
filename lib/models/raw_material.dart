class RawMaterial {
  final int materialId;
  final int factoryId;
  final String materialName;
  final double currentStock;
  final String unit;
  final double consumptionPerUnit;
  final double reorderLevel;
  final int safetyStockDays;

  const RawMaterial({
    required this.materialId,
    required this.factoryId,
    required this.materialName,
    required this.currentStock,
    required this.unit,
    required this.consumptionPerUnit,
    required this.reorderLevel,
    this.safetyStockDays = 3,
  });

  factory RawMaterial.fromJson(Map<String, dynamic> json) {
    return RawMaterial(
      materialId: json['material_id'] as int,
      factoryId: json['factory_id'] as int,
      materialName: json['material_name'] as String,
      currentStock: (json['current_stock'] as num).toDouble(),
      unit: json['unit'] as String? ?? 'kg',
      consumptionPerUnit: (json['consumption_per_unit'] as num).toDouble(),
      reorderLevel: (json['reorder_level'] as num?)?.toDouble() ?? 0,
      // Falls back to 3 when the column hasn't been migrated yet, so the
      // app keeps working against an older database schema.
      safetyStockDays: (json['safety_stock_days'] as num?)?.toInt() ?? 3,
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'material_name': materialName,
      'current_stock': currentStock,
      'unit': unit,
      'consumption_per_unit': consumptionPerUnit,
      'reorder_level': reorderLevel,
      'safety_stock_days': safetyStockDays,
    };
  }
}
