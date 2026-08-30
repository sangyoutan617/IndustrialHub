class DemandForecast {
  final int demandId;
  final int factoryId;
  final int productId;

  /// Display name. Read from the joined `products` row when the query
  /// embedded one (see DemandService.getForecasts) — demand_forecast's own
  /// `product_name` column is a write-time mirror kept only until it's
  /// dropped (multi-product capacity plan, phase k), and is never the
  /// source of truth once [productId] exists.
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
      productName:
          joinedProduct?['product_name'] as String? ??
          json['product_name'] as String,
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
      // Mirrored alongside product_id until the text column is dropped —
      // see the class doc comment.
      'product_name': productName,
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
