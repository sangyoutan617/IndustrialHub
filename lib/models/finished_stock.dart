class FinishedStock {
  final int stockId;
  final int factoryId;
  final int productId;

  /// Display name. Read from the joined `products` row when the query
  /// embedded one (see StockService.getStockList) — finished_stock's own
  /// `product_name` column is a write-time mirror kept only until it's
  /// dropped (multi-product capacity plan, phase k), and is never the
  /// source of truth once [productId] exists.
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
      productName:
          joinedProduct?['product_name'] as String? ??
          json['product_name'] as String,
      currentQuantity: json['current_quantity'] as int,
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'product_id': productId,
      // Mirrored alongside product_id until the text column is dropped —
      // see the class doc comment.
      'product_name': productName,
      'current_quantity': currentQuantity,
    };
  }
}
