class Factory {
  final int factoryId;
  final String factoryName;
  final String? location;
  final String? state;
  final String? msicCode;
  final String? ownerId;

  const Factory({
    required this.factoryId,
    required this.factoryName,
    this.location,
    this.state,
    this.msicCode,
    this.ownerId,
  });

  factory Factory.fromJson(Map<String, dynamic> json) {
    return Factory(
      factoryId: json['factory_id'] as int,
      factoryName: json['factory_name'] as String,
      location: json['location'] as String?,
      state: json['state'] as String?,
      msicCode: json['msic_code'] as String?,
      ownerId: json['owner_id'] as String?,
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
