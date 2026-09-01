class BomEntry {
  final int productId;
  final int materialId;
  final double quantityPerUnit;

  const BomEntry({
    required this.productId,
    required this.materialId,
    required this.quantityPerUnit,
  });

  factory BomEntry.fromJson(Map<String, dynamic> json) {
    return BomEntry(
      productId: json['product_id'] as int,
      materialId: json['material_id'] as int,
      quantityPerUnit: (json['quantity_per_unit'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'product_id': productId,
      'material_id': materialId,
      'quantity_per_unit': quantityPerUnit,
    };
  }
}
