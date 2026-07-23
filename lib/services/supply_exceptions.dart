/// Thrown when a delete is refused because other supply records still
/// reference the row — lets the UI explain *why*, instead of a raw
/// foreign-key error surfacing as a generic failure message.
class SupplyInUseException implements Exception {
  final String message;

  const SupplyInUseException(this.message);

  @override
  String toString() => message;
}
