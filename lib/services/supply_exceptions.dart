class SupplyInUseException implements Exception {
  final String message;

  const SupplyInUseException(this.message);

  @override
  String toString() => message;
}
