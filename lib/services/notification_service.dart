import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/formatters.dart';
import '../models/factory.dart';
import 'mrp_service.dart';
import 'supply_service.dart';

class MaterialDeliveryEvent {
  final int factoryId;
  final String materialName;
  final double quantity;
  final DateTime timestamp;

  const MaterialDeliveryEvent({
    required this.factoryId,
    required this.materialName,
    required this.quantity,
    required this.timestamp,
  });
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  final ValueNotifier<MaterialDeliveryEvent?> lastDelivery =
      ValueNotifier<MaterialDeliveryEvent?>(null);

  void clearDeliveryAlert() {
    lastDelivery.value = null;
  }

  Future<void> init() async {
    if (kIsWeb || _initialised) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const windows = WindowsInitializationSettings(
      appName: 'IndustrialHub',
      appUserModelId: 'com.industrialhub.app',
      guid: 'b6e7e6b0-6b6b-4f2e-9b0e-6e6f6b6b6b6b',
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      windows: windows,
    );
    await _plugin.initialize(settings: settings);
    _initialised = true;
    await _requestPermission();
  }

  Future<void> _requestPermission() async {
    if (kIsWeb) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'supply_alerts',
      'Supply alerts',
      channelDescription: 'Reorder-now and stock-out warnings',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const _deliveryDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'delivery_alerts',
      'Delivery alerts',
      channelDescription: 'Incoming material delivery notifications',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> notifySupplyRisk(Factory factory, SupplyOverview supply) async {
    if (kIsWeb) return;
    await init();

    final urgent = supply.plans
        .where(
          (p) =>
              p.risk == SupplyRisk.reorderNow ||
              p.risk == SupplyRisk.stockedOut,
        )
        .toList();
    if (urgent.isEmpty) return;

    urgent.sort((a, b) {
      final ad = a.orderByDate;
      final bd = b.orderByDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

    final first = urgent.first.material.materialName;
    final title = urgent.length == 1
        ? '$first needs reordering'
        : '${urgent.length} materials need reordering';
    final body =
        '${factory.factoryName}: reorder $first'
        '${urgent.length > 1 ? ' and ${urgent.length - 1} more' : ''} '
        'to avoid a stock-out.';

    await _plugin.show(
      id: factory.factoryId,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  Future<void> notifyDeliveryReceived({
    required int factoryId,
    required String materialName,
    required double quantity,
    String? factoryName,
  }) async {
    lastDelivery.value = MaterialDeliveryEvent(
      factoryId: factoryId,
      materialName: materialName,
      quantity: quantity,
      timestamp: DateTime.now(),
    );

    if (kIsWeb) return;
    await init();

    final title = 'Material Delivered';
    final qtyFormatted = '${formatRate(quantity)} units';
    final prefix = factoryName != null && factoryName.isNotEmpty
        ? '$factoryName: '
        : '';
    final body =
        '$prefix$qtyFormatted of $materialName received and added to stock.';

    final notifId = (factoryId * 10000 + (DateTime.now().millisecondsSinceEpoch % 10000)).toSigned(31);
    await _plugin.show(
      id: notifId,
      title: title,
      body: body,
      notificationDetails: _deliveryDetails,
    );
  }
}
