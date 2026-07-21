class Factory {
  final int factoryId;
  final String factoryName;
  final String? location;
  final String? state;
  final String? msicCode;

  const Factory({
    required this.factoryId,
    required this.factoryName,
    this.location,
    this.state,
    this.msicCode,
  });

  factory Factory.fromJson(Map<String, dynamic> json) {
    return Factory(
      factoryId: json['factory_id'] as int,
      factoryName: json['factory_name'] as String,
      location: json['location'] as String?,
      state: json['state'] as String?,
      msicCode: json['msic_code'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'factory_name': factoryName,
      'location': location,
      'state': state,
      'msic_code': msicCode,
    };
  }
}
