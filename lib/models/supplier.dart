class Supplier {
  final int supplierId;
  final String supplierName;
  final String? location;
  final int? materialId;
  final int leadTimeDays;
  final double reliabilityRating;
  final bool isSimulated;

  const Supplier({
    required this.supplierId,
    required this.supplierName,
    this.location,
    this.materialId,
    required this.leadTimeDays,
    required this.reliabilityRating,
    required this.isSimulated,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      supplierId: json['supplier_id'] as int,
      supplierName: json['supplier_name'] as String,
      location: json['location'] as String?,
      materialId: json['material_id'] as int?,
      leadTimeDays: json['lead_time_days'] as int,
      reliabilityRating: (json['reliability_rating'] as num?)?.toDouble() ?? 0,
      isSimulated: json['is_simulated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'supplier_name': supplierName,
      'location': location,
      'material_id': materialId,
      'lead_time_days': leadTimeDays,
      'reliability_rating': reliabilityRating,
    };
  }
}
