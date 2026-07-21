class IpiBenchmark {
  final DateTime date;
  final String division;
  final double productionIndex;
  final String? divisionName;

  const IpiBenchmark({
    required this.date,
    required this.division,
    required this.productionIndex,
    this.divisionName,
  });

  factory IpiBenchmark.fromJson(Map<String, dynamic> json) {
    return IpiBenchmark(
      date: DateTime.parse(json['date'] as String),
      division: json['division'] as String,
      productionIndex: (json['production_index'] as num).toDouble(),
      divisionName: json['division_name'] as String?,
    );
  }
}
