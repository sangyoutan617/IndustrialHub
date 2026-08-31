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

  /// Which step of the production flow this machine sits at (e.g. "Mixing",
  /// "Filling", "Packaging"). Machines sharing a stage run in **parallel** —
  /// their capacities add. Distinct stages form a serial flow, so the
  /// product's machine ceiling is the **slowest** stage (C1). Null/blank
  /// means "its own stage" — a machine with no stage set is treated as a
  /// standalone step.
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

  /// True when this row stands for more than one physical machine — the
  /// signal the UI uses to show unit counts and the "machines down" field.
  bool get isGroup => unitCount > 1;

  /// The stage this machine belongs to for capacity grouping. Falls back to a
  /// per-machine key so an unstaged machine forms its own single-machine
  /// stage. Case-folded so "Filling" and "filling" are the same stage.
  String get stageKey {
    final s = stage?.trim().toLowerCase() ?? '';
    return s.isEmpty ? 'machine:$machineId' : s;
  }

  /// Human-readable stage label, or null when none was set.
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
