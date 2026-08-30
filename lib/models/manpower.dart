class Manpower {
  final int manpowerId;
  final int factoryId;
  final int productId;
  final String shiftName;
  final int workerCount;
  final double shiftHours;
  final double outputPerWorkerHour;
  final bool isSimulated;

  const Manpower({
    required this.manpowerId,
    required this.factoryId,
    required this.productId,
    required this.shiftName,
    required this.workerCount,
    required this.shiftHours,
    required this.outputPerWorkerHour,
    required this.isSimulated,
  });

  factory Manpower.fromJson(Map<String, dynamic> json) {
    return Manpower(
      manpowerId: json['manpower_id'] as int,
      factoryId: json['factory_id'] as int,
      productId: json['product_id'] as int,
      shiftName: json['shift_name'] as String,
      workerCount: json['worker_count'] as int,
      shiftHours: (json['shift_hours'] as num).toDouble(),
      outputPerWorkerHour: (json['output_per_worker_hour'] as num).toDouble(),
      isSimulated: json['is_simulated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'product_id': productId,
      'shift_name': shiftName,
      'worker_count': workerCount,
      'shift_hours': shiftHours,
      'output_per_worker_hour': outputPerWorkerHour,
    };
  }
}
