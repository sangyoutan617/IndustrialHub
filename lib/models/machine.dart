class MachineStatus {
  static const active = 'Active';
  static const underMaintenance = 'Under Maintenance';
  static const downtime = 'Downtime';
  static const repair = 'Repair';
  static const all = [active, underMaintenance, downtime, repair];
}

class Machine {
  final int machineId;
  final int factoryId;
  final int productId;
  final String machineName;
  final double ratedOutputPerHour;
  final double operatingHoursPerDay;

  final int unitCount;

  final String? stage;
  final String status;
  final bool isSimulated;

  const Machine({
    required this.machineId,
    required this.factoryId,
    required this.productId,
    required this.machineName,
    required this.ratedOutputPerHour,
    required this.operatingHoursPerDay,
    this.unitCount = 1,
    this.stage,
    required this.status,
    required this.isSimulated,
  });

  bool get isActive => status == MachineStatus.active;
  bool get isDowntime => status == MachineStatus.downtime;
  bool get isRepair => status == MachineStatus.repair;

  bool get isGroup => unitCount > 1;

  String get stageKey {
    final s = stage?.trim().toLowerCase() ?? '';
    return s.isEmpty ? 'machine:$machineId' : s;
  }

  String? get stageLabel {
    final s = stage?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  factory Machine.fromJson(Map<String, dynamic> json) {
    return Machine(
      machineId: json['machine_id'] as int,
      factoryId: json['factory_id'] as int,
      productId: json['product_id'] as int,
      machineName: json['machine_name'] as String,
      ratedOutputPerHour: (json['rated_output_per_hour'] as num).toDouble(),
      operatingHoursPerDay: (json['operating_hours_per_day'] as num).toDouble(),
      unitCount: (json['unit_count'] as num?)?.toInt() ?? 1,
      stage: json['stage'] as String?,
      status: json['status'] as String,
      isSimulated: json['is_simulated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'product_id': productId,
      'machine_name': machineName,
      'rated_output_per_hour': ratedOutputPerHour,
      'operating_hours_per_day': operatingHoursPerDay,
      'unit_count': unitCount,
      'stage': stage?.trim().isEmpty ?? true ? null : stage!.trim(),
      'status': status,
    };
  }
}
