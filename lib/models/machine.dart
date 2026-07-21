class Machine {
  final int machineId;
  final int factoryId;
  final String machineName;
  final double ratedOutputPerHour;
  final double operatingHoursPerDay;
  final double uptimePercent;
  final String status;
  final bool isSimulated;

  const Machine({
    required this.machineId,
    required this.factoryId,
    required this.machineName,
    required this.ratedOutputPerHour,
    required this.operatingHoursPerDay,
    required this.uptimePercent,
    required this.status,
    required this.isSimulated,
  });

  bool get isActive => status == 'Active';

  factory Machine.fromJson(Map<String, dynamic> json) {
    return Machine(
      machineId: json['machine_id'] as int,
      factoryId: json['factory_id'] as int,
      machineName: json['machine_name'] as String,
      ratedOutputPerHour: (json['rated_output_per_hour'] as num).toDouble(),
      operatingHoursPerDay: (json['operating_hours_per_day'] as num).toDouble(),
      uptimePercent: (json['uptime_percent'] as num).toDouble(),
      status: json['status'] as String,
      isSimulated: json['is_simulated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'machine_name': machineName,
      'rated_output_per_hour': ratedOutputPerHour,
      'operating_hours_per_day': operatingHoursPerDay,
      'uptime_percent': uptimePercent,
      'status': status,
    };
  }
}
