class FinishedStock {
  final int stockId;
  final int factoryId;
  final String productName;
  final int currentQuantity;

  const FinishedStock({
    required this.stockId,
    required this.factoryId,
    required this.productName,
    required this.currentQuantity,
  });

  factory FinishedStock.fromJson(Map<String, dynamic> json) {
    return FinishedStock(
      stockId: json['stock_id'] as int,
      factoryId: json['factory_id'] as int,
      productName: json['product_name'] as String,
      currentQuantity: json['current_quantity'] as int,
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'product_name': productName,
      'current_quantity': currentQuantity,
    };
  }
}
