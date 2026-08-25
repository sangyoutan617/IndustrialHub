/// Movement types for the raw-material ledger.
///
/// `consumption` is stock issued to production (negative delta), `receipt` is
/// stock arriving (positive delta — normally written by a delivery), and
/// `adjustment` is a manual correction that can go either way.
class RawMaterialMovementType {
  static const consumption = 'consumption';
  static const receipt = 'receipt';
  static const adjustment = 'adjustment';
  static const all = [consumption, receipt, adjustment];
}

/// One entry in a raw material's stock ledger. Mirrors [StockMovement] but for
/// raw materials — finished goods and raw materials keep separate ledgers.
class RawMaterialMovement {
  final int movementId;
  final int materialId;
  final int factoryId;
  final String movementType;
  final double quantity;
  final DateTime movementDate;
  final String? note;
  final bool isSimulated;

  const RawMaterialMovement({
    required this.movementId,
    required this.materialId,
    required this.factoryId,
    required this.movementType,
    required this.quantity,
    required this.movementDate,
    this.note,
    required this.isSimulated,
  });

  factory RawMaterialMovement.fromJson(Map<String, dynamic> json) {
    return RawMaterialMovement(
      movementId: (json['movement_id'] as num).toInt(),
      materialId: json['material_id'] as int,
      factoryId: json['factory_id'] as int,
      movementType: json['movement_type'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      movementDate: DateTime.parse(json['movement_date'] as String),
      note: json['note'] as String?,
      isSimulated: json['is_simulated'] as bool? ?? false,
    );
  }
}
