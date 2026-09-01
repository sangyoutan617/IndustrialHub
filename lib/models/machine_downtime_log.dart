class MachineDowntimeLog {
  final int logId;
  final int machineId;
  final int factoryId;
  final DateTime logDate;
  final double downtimeHours;

  final int machinesDown;
  final String? reason;
  final DateTime? repairStartedAt;
  final DateTime? repairedAt;
  final bool isSimulated;

  const MachineDowntimeLog({
    required this.logId,
    required this.machineId,
    required this.factoryId,
    required this.logDate,
    required this.downtimeHours,
    this.machinesDown = 1,
    this.reason,
    this.repairStartedAt,
    this.repairedAt,
    required this.isSimulated,
  });

  bool get resolved => repairedAt != null;

  factory MachineDowntimeLog.fromJson(Map<String, dynamic> json) {
    return MachineDowntimeLog(
      logId: (json['log_id'] as num).toInt(),
      machineId: json['machine_id'] as int,
      factoryId: json['factory_id'] as int,
      logDate: DateTime.parse(json['log_date'] as String),
      downtimeHours: (json['downtime_hours'] as num).toDouble(),
      machinesDown: (json['machines_down'] as num?)?.toInt() ?? 1,
      reason: json['reason'] as String?,
      repairStartedAt: json['repair_started_at'] != null
          ? DateTime.parse(json['repair_started_at'] as String)
          : null,
      repairedAt: json['repaired_at'] != null
          ? DateTime.parse(json['repaired_at'] as String)
          : null,
      isSimulated: json['is_simulated'] as bool? ?? false,
    );
  }
}
