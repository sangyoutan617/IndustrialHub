class PurchaseOrderStatus {
  static const pending = 'Pending';
  static const processing = 'Processing';
  static const shipped = 'Shipped';
  static const delivered = 'Delivered';
  static const cancelled = 'Cancelled';
  static const all = [pending, processing, shipped, delivered, cancelled];
}

class PurchaseOrder {
  final int poId;
  final int supplierId;
  final int materialId;
  final double quantity;
  final DateTime orderDate;
  final DateTime? expectedDelivery;
  final DateTime? deliveredAt;
  final String status;
  final bool isSimulated;

  const PurchaseOrder({
    required this.poId,
    required this.supplierId,
    required this.materialId,
    required this.quantity,
    required this.orderDate,
    this.expectedDelivery,
    this.deliveredAt,
    required this.status,
    required this.isSimulated,
  });

  /// True once this PO can no longer arrive or change — used to decide
  /// whether it still counts toward incoming stock in the MRP projection.
  bool get isClosed =>
      status == PurchaseOrderStatus.delivered ||
      status == PurchaseOrderStatus.cancelled;

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      poId: json['po_id'] as int,
      supplierId: json['supplier_id'] as int,
      materialId: json['material_id'] as int,
      quantity: (json['quantity'] as num).toDouble(),
      orderDate: DateTime.parse(json['order_date'] as String),
      expectedDelivery: json['expected_delivery'] != null
          ? DateTime.parse(json['expected_delivery'] as String)
          : null,
      // Column added alongside safety_stock_days; absent on an
      // un-migrated database, so this stays null rather than throwing.
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      status: json['status'] as String,
      isSimulated: json['is_simulated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'supplier_id': supplierId,
      'material_id': materialId,
      'quantity': quantity,
      'order_date': orderDate.toIso8601String().substring(0, 10),
      'expected_delivery': expectedDelivery?.toIso8601String().substring(0, 10),
      'status': status,
    };
  }
}
