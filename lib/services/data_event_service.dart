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

class DataEventService {
  DataEventService._();
  static final DataEventService instance = DataEventService._();

  final ValueNotifier<DataChangeEvent?> changeEvent =
      ValueNotifier<DataChangeEvent?>(null);

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
