class Product {
  final int productId;
  final int factoryId;
  final String productName;
  final String unit;

  final bool isGeneral;
  final String status;

  const Product({
    required this.productId,
    required this.factoryId,
    required this.productName,
    this.unit = 'units',
    this.isGeneral = false,
    this.status = 'active',
  });

  bool get isArchived => status == 'archived';

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      productId: json['product_id'] as int,
      factoryId: json['factory_id'] as int,
      productName: json['product_name'] as String,
      unit: json['unit'] as String? ?? 'units',
      isGeneral: json['is_general'] as bool? ?? false,
      status: json['status'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'product_name': productName,
      'unit': unit,
    };
  }
}
