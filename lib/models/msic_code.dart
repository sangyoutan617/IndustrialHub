class MsicCode {
  final String msicCode;
  final String description;
  final String? category;

  const MsicCode({
    required this.msicCode,
    required this.description,
    this.category,
  });

  String get division =>
      msicCode.length >= 2 ? msicCode.substring(0, 2) : msicCode;

  factory MsicCode.fromJson(Map<String, dynamic> json) {
    return MsicCode(
      msicCode: json['msic_code'] as String,
      description: json['description'] as String,
      category: json['category'] as String?,
    );
  }
}
