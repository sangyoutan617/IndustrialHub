import 'package:flutter/foundation.dart';

enum DataChangeSource {
  stock,
  demand,
  supply,
  order,
  capacity,
  production,
  general,
}

class DataChangeEvent {
  final int factoryId;
  final DataChangeSource source;
  final DateTime timestamp;

  const DataChangeEvent({
    required this.factoryId,
    required this.source,
    required this.timestamp,
  });
}

/// A real-time reactive event bus that notifies active screens whenever
/// data changes across any module, eliminating the need for manual refreshes.
class DataEventService {
  DataEventService._();
  static final DataEventService instance = DataEventService._();

  final ValueNotifier<DataChangeEvent?> changeEvent =
      ValueNotifier<DataChangeEvent?>(null);

  /// Broadcasts a data change event for [factoryId], automatically prompting
  /// all active tabs and screens to reload immediately in the background.
  void notifyChanged({
    required int factoryId,
    DataChangeSource source = DataChangeSource.general,
  }) {
    changeEvent.value = DataChangeEvent(
      factoryId: factoryId,
      source: source,
      timestamp: DateTime.now(),
    );
  }
}
