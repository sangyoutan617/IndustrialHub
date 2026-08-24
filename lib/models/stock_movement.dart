class StockMovementType {
  static const productionIn = 'production_in';
  static const shipmentOut = 'shipment_out';
  static const damaged = 'damaged';
  static const returned = 'returned';
  static const adjustment = 'adjustment';
  static const all = [productionIn, shipmentOut, damaged, returned, adjustment];
}

class StockMovement {
  final int movementId;
  final int stockId;
  final String movementType;
  final int quantity;
  final DateTime movementDate;
  final String? note;
  final bool isSimulated;

  const StockMovement({
    required this.movementId,
    required this.stockId,
    required this.movementType,
    required this.quantity,
    required this.movementDate,
    this.note,
    required this.isSimulated,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      movementId: json['movement_id'] as int,
      stockId: json['stock_id'] as int,
      movementType: json['movement_type'] as String,
      quantity: json['quantity'] as int,
      movementDate: DateTime.parse(json['movement_date'] as String),
      note: json['note'] as String?,
      isSimulated: json['is_simulated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toInsertJson(int stockId) {
    return {
      'stock_id': stockId,
      'movement_type': movementType,
      'quantity': quantity,
      'movement_date': movementDate.toIso8601String().substring(0, 10),
      'note': note,
    };
  }
}
