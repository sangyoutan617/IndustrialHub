class DemandForecast {
  final int demandId;
  final int factoryId;
  final int productId;

  /// Display name, read from the joined `products` row (see
  /// DemandService.getForecasts) — demand_forecast carries no product-name
  /// column of its own any more, [productId] is the only source of truth.
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
      // Falls back rather than throwing if a caller's query ever forgets
      // to embed the join — a wrong-looking name beats a crash.
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

  /// Whether this forecast is in effect on [day]. An open-ended period (null
  /// start or end) is always in effect on that side, so a forecast with no
  /// dates at all counts every day — keeping rows created before periods
  /// existed exactly as they behaved before. Compared date-only, and both
  /// boundaries are inclusive.
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

  /// The subset of [forecasts] in effect on [day] — used so an expired or
  /// future forecast no longer inflates today's demand / planned production.
  /// Pure — no DB.
  static List<DemandForecast> activeOn(
    Iterable<DemandForecast> forecasts,
    DateTime day,
  ) => forecasts.where((f) => f.isActiveOn(day)).toList();
}
