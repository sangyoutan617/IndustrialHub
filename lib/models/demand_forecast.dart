class DemandForecast {
  final int demandId;
  final int factoryId;
  final int productId;

  final String productName;
  final int requiredPerDay;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  const DemandForecast({
    required this.demandId,
    required this.factoryId,
    required this.productId,
    required this.productName,
    required this.requiredPerDay,
    this.periodStart,
    this.periodEnd,
  });

  factory DemandForecast.fromJson(Map<String, dynamic> json) {
    final joinedProduct = json['products'] as Map<String, dynamic>?;
    return DemandForecast(
      demandId: json['demand_id'] as int,
      factoryId: json['factory_id'] as int,
      productId: json['product_id'] as int,
      productName: joinedProduct?['product_name'] as String? ?? 'Unknown product',
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
      'product_id': productId,
      'required_per_day': requiredPerDay,
      'period_start': periodStart?.toIso8601String().substring(0, 10),
      'period_end': periodEnd?.toIso8601String().substring(0, 10),
    };
  }

  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final start = periodStart;
    if (start != null &&
        d.isBefore(DateTime(start.year, start.month, start.day))) {
      return false;
    }
    final end = periodEnd;
    if (end != null && d.isAfter(DateTime(end.year, end.month, end.day))) {
      return false;
    }
    return true;
  }

  static List<DemandForecast> activeOn(
    Iterable<DemandForecast> forecasts,
    DateTime day,
  ) => forecasts.where((f) => f.isActiveOn(day)).toList();
}
