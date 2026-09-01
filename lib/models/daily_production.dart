class DailyProduction {
  final int dailyId;
  final int factoryId;

  final int productId;
  final DateTime logDate;
  final int actualOutput;
  final double? machineCapacity;
  final double? manpowerCapacity;
  final double? effectiveCeiling;
  final String? bottleneck;
  final double? utilisationPercent;
  final double downtimeHours;
  final bool isSimulated;

  const DailyProduction({
    required this.dailyId,
    required this.factoryId,
    required this.productId,
    required this.logDate,
    required this.actualOutput,
    this.machineCapacity,
    this.manpowerCapacity,
    this.effectiveCeiling,
    this.bottleneck,
    this.utilisationPercent,
    required this.downtimeHours,
    required this.isSimulated,
  });

  factory DailyProduction.fromJson(Map<String, dynamic> json) {
    return DailyProduction(
      dailyId: json['daily_id'] as int,
      factoryId: json['factory_id'] as int,
      productId: json['product_id'] as int,
      logDate: DateTime.parse(json['log_date'] as String),
      actualOutput: json['actual_output'] as int,
      machineCapacity: (json['machine_capacity'] as num?)?.toDouble(),
      manpowerCapacity: (json['manpower_capacity'] as num?)?.toDouble(),
      effectiveCeiling: (json['effective_ceiling'] as num?)?.toDouble(),
      bottleneck: json['bottleneck'] as String?,
      utilisationPercent: (json['utilisation_percent'] as num?)?.toDouble(),
      downtimeHours: (json['downtime_hours'] as num?)?.toDouble() ?? 0,
      isSimulated: json['is_simulated'] as bool? ?? false,
    );
  }
}
