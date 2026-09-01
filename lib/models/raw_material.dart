class RawMaterial {
  final int materialId;
  final int factoryId;
  final String materialName;
  final double currentStock;
  final String unit;
  final int safetyStockDays;

  final double? unitCost;

  const RawMaterial({
    required this.materialId,
    required this.factoryId,
    required this.materialName,
    required this.currentStock,
    required this.unit,
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
      safetyStockDays: (json['safety_stock_days'] as num?)?.toInt() ?? 3,
      unitCost: (json['unit_cost'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'material_name': materialName,
      'current_stock': currentStock,
      'unit': unit,
      'safety_stock_days': safetyStockDays,
      'unit_cost': unitCost,
    };
  }
}
