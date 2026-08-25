class Supplier {
  final int supplierId;
  final String supplierName;
  final String? location;
  final int? materialId;
  final int leadTimeDays;
  final double reliabilityRating;
  final bool isSimulated;

  /// Contact details so a supplier the app recommends reordering from is
  /// actually reachable. All optional — null when not recorded.
  final String? contactPerson;
  final String? phone;
  final String? email;

  const Supplier({
    required this.supplierId,
    required this.supplierName,
    this.location,
    this.materialId,
    required this.leadTimeDays,
    required this.reliabilityRating,
    required this.isSimulated,
    this.contactPerson,
    this.phone,
    this.email,
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
      // Absent on an un-migrated database — stay null rather than throwing.
      contactPerson: json['contact_person'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'supplier_name': supplierName,
      'location': location,
      'material_id': materialId,
      'lead_time_days': leadTimeDays,
      'reliability_rating': reliabilityRating,
      'contact_person': contactPerson,
      'phone': phone,
      'email': email,
    };
  }
}
