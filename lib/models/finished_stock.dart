class FinishedStock {
  final int stockId;
  final int factoryId;
  final int productId;

  final String productName;
  final int currentQuantity;
  final String productStatus;

  const FinishedStock({
    required this.stockId,
    required this.factoryId,
    required this.productId,
    required this.productName,
    required this.currentQuantity,
    this.productStatus = 'active',
  });

  bool get isArchived => productStatus == 'archived';

  factory FinishedStock.fromJson(Map<String, dynamic> json) {
    final joinedProduct = json['products'] as Map<String, dynamic>?;
    return FinishedStock(
      stockId: json['stock_id'] as int,
      factoryId: json['factory_id'] as int,
      productId: json['product_id'] as int,
      productName: joinedProduct?['product_name'] as String? ?? 'Unknown product',
      currentQuantity: json['current_quantity'] as int,
      productStatus: joinedProduct?['status'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'product_id': productId,
      'current_quantity': currentQuantity,
    };
  }
}
