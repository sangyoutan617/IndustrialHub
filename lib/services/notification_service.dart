import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/factory.dart';
import 'mrp_service.dart';
import 'supply_service.dart';

/// Surfaces supply-risk alerts as OS notifications. The risk itself is
/// computed by [MrpService] (via [SupplyService]); this only decides whether
/// something is urgent enough to notify about and shows it. Entirely a no-op
/// on web, where local notifications aren't supported.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  Future<void> init() async {
    if (kIsWeb || _initialised) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
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

  /// Fires one summary notification when [supply] contains materials that
  /// must be reordered now (or are already stocked out). No-op on web, and
  /// when nothing is urgent. The id is keyed by factory so alerts for
  /// different factories don't overwrite each other.
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
}
