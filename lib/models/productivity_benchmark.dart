class ProductivityBenchmark {
  final String sector;
  final int year;
  final double? valueAddedPerWorker;
  final double? valueAddedPerHour;

  const ProductivityBenchmark({
    required this.sector,
    required this.year,
    this.valueAddedPerWorker,
    this.valueAddedPerHour,
  });

  factory ProductivityBenchmark.fromJson(Map<String, dynamic> json) {
    return ProductivityBenchmark(
      sector: json['sector'] as String,
      year: json['year'] as int,
      valueAddedPerWorker: (json['value_added_per_worker'] as num?)?.toDouble(),
      valueAddedPerHour: (json['value_added_per_hour'] as num?)?.toDouble(),
    );
  }
}
