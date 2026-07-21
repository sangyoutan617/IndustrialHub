class DemandForecast {
  final int demandId;
  final int factoryId;
  final String productName;
  final int requiredPerDay;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  const DemandForecast({
    required this.demandId,
    required this.factoryId,
    required this.productName,
    required this.requiredPerDay,
    this.periodStart,
    this.periodEnd,
  });

  factory DemandForecast.fromJson(Map<String, dynamic> json) {
    return DemandForecast(
      demandId: json['demand_id'] as int,
      factoryId: json['factory_id'] as int,
      productName: json['product_name'] as String,
      requiredPerDay: json['required_per_day'] as int,
      periodStart: json['period_start'] != null
          ? DateTime.parse(json['period_start'] as String)
          : null,
      periodEnd: json['period_end'] != null
          ? DateTime.parse(json['period_end'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'product_name': productName,
      'required_per_day': requiredPerDay,
      'period_start': periodStart?.toIso8601String().substring(0, 10),
      'period_end': periodEnd?.toIso8601String().substring(0, 10),
    };
  }
}
