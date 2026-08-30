class FinishedStock {
  final int stockId;
  final int factoryId;
  final int productId;

  /// Display name, read from the joined `products` row (see
  /// StockService.getStockList) — finished_stock carries no product-name
  /// column of its own any more, [productId] is the only source of truth.
  final String productName;
  final int currentQuantity;

  const FinishedStock({
    required this.stockId,
    required this.factoryId,
    required this.productId,
    required this.productName,
    required this.currentQuantity,
  });

  factory FinishedStock.fromJson(Map<String, dynamic> json) {
    final joinedProduct = json['products'] as Map<String, dynamic>?;
    return FinishedStock(
      stockId: json['stock_id'] as int,
      factoryId: json['factory_id'] as int,
      productId: json['product_id'] as int,
      // Falls back rather than throwing if a caller's query ever forgets
      // to embed the join — a wrong-looking name beats a crash.
      productName: joinedProduct?['product_name'] as String? ?? 'Unknown product',
      currentQuantity: json['current_quantity'] as int,
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
