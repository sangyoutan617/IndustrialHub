/// The four states a machine's `status` can be in. `active`/`underMaintenance`
/// are freely selectable in the machine form. `downtime`/`repair` are the two
/// steps of the unplanned-breakdown workflow — normally reached via
/// [MachineDowntimeService]'s actions (log downtime → start repair → mark
/// repaired) rather than picked directly, though the form still allows a
/// manual correction if a machine's status ever gets stuck.
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

  /// How many identical physical machines this one row stands for. A row is
  /// a *group*: `unit_count` units that share a rate, a schedule and a
  /// status. Defaults to 1, so a plain single machine is just a group of one.
  /// Capacity (C1) counts `rated × hours × unitCount`.
  final int unitCount;
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
    required this.status,
    required this.isSimulated,
  });

  bool get isActive => status == MachineStatus.active;
  bool get isDowntime => status == MachineStatus.downtime;
  bool get isRepair => status == MachineStatus.repair;

  /// True when this row stands for more than one physical machine — the
  /// signal the UI uses to show unit counts and the "machines down" field.
  bool get isGroup => unitCount > 1;

  factory Machine.fromJson(Map<String, dynamic> json) {
    return Machine(
      machineId: json['machine_id'] as int,
      factoryId: json['factory_id'] as int,
      productId: json['product_id'] as int,
      machineName: json['machine_name'] as String,
      ratedOutputPerHour: (json['rated_output_per_hour'] as num).toDouble(),
      operatingHoursPerDay: (json['operating_hours_per_day'] as num).toDouble(),
      unitCount: (json['unit_count'] as num?)?.toInt() ?? 1,
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
      'status': status,
    };
  }
}
