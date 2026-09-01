import '../models/bom_entry.dart';
import '../models/purchase_order.dart';
import '../models/raw_material.dart';
import '../models/supplier.dart';

class InboundDelivery {
  final DateTime date;
  final double quantity;

  const InboundDelivery(this.date, this.quantity);
}

class MrpProjection {
  final DateTime? stockOutDate;

  final List<double> dailyBalances;

  final double? daysOfCover;

  const MrpProjection({
    required this.stockOutDate,
    required this.dailyBalances,
    required this.daysOfCover,
  });
}

enum SupplyRisk {
  healthy,

  watch,

  reorderNow,

  stockedOut,

  noSupplier,
}

class MaterialPlan {
  final RawMaterial material;
  final double burnRatePerDay;
  final double onHand;
  final double inboundTotal;

  final double overdueInboundTotal;
  final int overdueOrderCount;
  final Supplier? bestSupplier;
  final int? effectiveLeadDays;
  final double? daysOfCover;
  final DateTime? stockOutDate;
  final DateTime? orderByDate;
  final double? suggestedQty;
  final SupplyRisk risk;

  final double reorderLevel;
  final bool belowReorderLevel;
  final List<double> dailyBalances;

  const MaterialPlan({
    required this.material,
    required this.burnRatePerDay,
    required this.onHand,
    required this.inboundTotal,
    required this.overdueInboundTotal,
    required this.overdueOrderCount,
    required this.bestSupplier,
    required this.effectiveLeadDays,
    required this.daysOfCover,
    required this.stockOutDate,
    required this.orderByDate,
    required this.suggestedQty,
    required this.risk,
    required this.reorderLevel,
    required this.belowReorderLevel,
    required this.dailyBalances,
  });

  bool get needsAttention =>
      risk == SupplyRisk.reorderNow ||
      risk == SupplyRisk.stockedOut ||
      risk == SupplyRisk.watch ||
      belowReorderLevel;
}

class SupplierComparison {
  final Supplier supplier;
  final int quotedLeadDays;
  final int effectiveLeadDays;
  final double reliabilityRating;
  final double? onTimeRate;
  final int historyCount;

  final double? unitPrice;
  final bool isRecommended;
  final String reason;

  const SupplierComparison({
    required this.supplier,
    required this.quotedLeadDays,
    required this.effectiveLeadDays,
    required this.reliabilityRating,
    required this.onTimeRate,
    required this.historyCount,
    required this.unitPrice,
    required this.isRecommended,
    required this.reason,
  });
}

class MrpService {
  static const int reviewPeriodDays = 14;

  static const int defaultHorizonDays = 180;

  static const int watchWindowDays = 7;

  static const double reorderLevelWeeklyBuffer = 0.2;

  const MrpService._();

  static double reorderLevelFor({required double burnRatePerDay}) {
    final weeklyConsumption = burnRatePerDay * 7;
    return weeklyConsumption * reorderLevelWeeklyBuffer;
  }

  static double aggregateBurnRate({
    required Map<int, double> plannedPerProduct,
    required List<BomEntry> bom,
    required int materialId,
  }) {
    var total = 0.0;
    for (final entry in bom) {
      if (entry.materialId != materialId) continue;
      total += (plannedPerProduct[entry.productId] ?? 0) * entry.quantityPerUnit;
    }
    return total;
  }

  static Map<int, double> computeProductionConsumption(
    Iterable<BomEntry> bom,
    int unitsProduced,
  ) {
    final result = <int, double>{};
    for (final entry in bom) {
      final used = entry.quantityPerUnit * unitsProduced;
      if (used > 0) result[entry.materialId] = used;
    }
    return result;
  }

  static List<RawMaterial> insufficientMaterials({
    required Iterable<RawMaterial> materials,
    required Iterable<BomEntry> bom,
    required int unitsProduced,
  }) {
    final ratePerMaterial = {
      for (final entry in bom) entry.materialId: entry.quantityPerUnit,
    };
    return materials.where((m) {
      final rate = ratePerMaterial[m.materialId];
      if (rate == null) return false;
      return rate * unitsProduced > m.currentStock;
    }).toList();
  }

  static double? orderTotal(PurchaseOrder order) {
    final price = order.unitPrice;
    if (price == null) return null;
    return order.quantity * price;
  }

  static double inventoryValue(Iterable<RawMaterial> materials) {
    var total = 0.0;
    for (final m in materials) {
      final cost = m.unitCost;
      if (cost != null) total += m.currentStock * cost;
    }
    return total;
  }

  static double? latestUnitPrice(Iterable<PurchaseOrder> supplierHistory) {
    PurchaseOrder? latest;
    for (final o in supplierHistory) {
      if (o.unitPrice == null) continue;
      if (latest == null || o.orderDate.isAfter(latest.orderDate)) latest = o;
    }
    return latest?.unitPrice;
  }

  static int effectiveLeadDays(Supplier supplier) {
    final ratingGap = (5 - supplier.reliabilityRating).clamp(0, 5);
    final factor = 1 + 0.5 * (ratingGap / 5);
    return (supplier.leadTimeDays * factor).ceil();
  }

  static Supplier? bestSupplier(Iterable<Supplier> suppliers) {
    final list = suppliers.toList();
    if (list.isEmpty) return null;
    list.sort((a, b) {
      final leadCompare = effectiveLeadDays(a).compareTo(effectiveLeadDays(b));
      if (leadCompare != 0) return leadCompare;
      return b.reliabilityRating.compareTo(a.reliabilityRating);
    });
    return list.first;
  }

  static MrpProjection project({
    required double openingStock,
    required double burnRatePerDay,
    required List<InboundDelivery> inbound,
    required DateTime today,
    int horizonDays = defaultHorizonDays,
  }) {
    final start = DateTime(today.year, today.month, today.day);

    final inboundByDay = <DateTime, double>{};
    for (final delivery in inbound) {
      var day = DateTime(
        delivery.date.year,
        delivery.date.month,
        delivery.date.day,
      );
      if (day.isBefore(start)) day = start;
      inboundByDay[day] = (inboundByDay[day] ?? 0) + delivery.quantity;
    }

    final balances = <double>[];
    var balance = openingStock;
    DateTime? stockOutDate;
    var daysOfCover = 0;

    for (var i = 0; i <= horizonDays; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      balance += inboundByDay[day] ?? 0;
      if (burnRatePerDay > 0) balance -= burnRatePerDay;
      balances.add(balance);
      if (stockOutDate == null && balance < 0) {
        stockOutDate = day;
        daysOfCover = i;
      }
    }

    return MrpProjection(
      stockOutDate: stockOutDate,
      dailyBalances: balances,
      daysOfCover: (burnRatePerDay > 0 && stockOutDate != null)
          ? daysOfCover.toDouble()
          : null,
    );
  }

  static DateTime? orderByDate({
    required DateTime? stockOutDate,
    required int effectiveLeadDays,
    required int safetyStockDays,
  }) {
    if (stockOutDate == null) return null;
    return stockOutDate.subtract(
      Duration(days: effectiveLeadDays + safetyStockDays),
    );
  }

  static SupplyRisk riskFor({
    required DateTime? orderByDate,
    required DateTime? stockOutDate,
    required DateTime today,
    required bool hasSupplier,
  }) {
    if (!hasSupplier) return SupplyRisk.noSupplier;
    final day = DateTime(today.year, today.month, today.day);
    if (stockOutDate != null && !stockOutDate.isAfter(day)) {
      return SupplyRisk.stockedOut;
    }
    if (orderByDate != null && !orderByDate.isAfter(day)) {
      return SupplyRisk.reorderNow;
    }
    if (orderByDate != null &&
        orderByDate.difference(day).inDays <= watchWindowDays) {
      return SupplyRisk.watch;
    }
    return SupplyRisk.healthy;
  }

  static double suggestedQty({
    required double burnRatePerDay,
    required double onHand,
    required double inboundTotal,
    required int effectiveLeadDays,
    required int safetyStockDays,
  }) {
    final targetCoverDays =
        effectiveLeadDays + safetyStockDays + reviewPeriodDays;
    final raw = burnRatePerDay * targetCoverDays - onHand - inboundTotal;
    if (raw <= 0) return 0;
    return (raw / 10).ceil() * 10.0;
  }

  static double _inboundWithinCoverWindow({
    required List<InboundDelivery> inbound,
    required DateTime startOfToday,
    required int effectiveLeadDays,
    required int safetyStockDays,
  }) {
    final windowEnd = startOfToday.add(
      Duration(days: effectiveLeadDays + safetyStockDays + reviewPeriodDays),
    );
    return inbound
        .where((delivery) => !delivery.date.isAfter(windowEnd))
        .fold<double>(0, (sum, d) => sum + d.quantity);
  }

  static MaterialPlan buildPlan({
    required RawMaterial material,
    required List<Supplier> suppliersForMaterial,
    required List<PurchaseOrder> ordersForMaterial,
    required double burnRatePerDay,
    required DateTime today,
  }) {
    final reorderLevel = reorderLevelFor(burnRatePerDay: burnRatePerDay);
    final supplier = bestSupplier(suppliersForMaterial);
    final leadDays = supplier != null ? effectiveLeadDays(supplier) : null;

    final suppliersById = <int, Supplier>{
      for (final s in suppliersForMaterial) s.supplierId: s,
    };

    final startOfToday = DateTime(today.year, today.month, today.day);
    final openOrders = ordersForMaterial.where((o) => !o.isClosed).toList();
    final inboundTotal = openOrders.fold<double>(
      0,
      (sum, o) => sum + o.quantity,
    );
    final inbound = openOrders.map((order) {
      final orderSupplier = suppliersById[order.supplierId];
      final fallbackLeadDays = orderSupplier != null
          ? effectiveLeadDays(orderSupplier)
          : (leadDays ?? 0);
      final date =
          order.expectedDelivery ??
          order.orderDate.add(Duration(days: fallbackLeadDays));
      return InboundDelivery(date, order.quantity);
    }).toList();

    final overdueOrders = inbound
        .where((delivery) => delivery.date.isBefore(startOfToday))
        .toList();
    final overdueInboundTotal = overdueOrders.fold<double>(
      0,
      (sum, d) => sum + d.quantity,
    );

    final projection = project(
      openingStock: material.currentStock,
      burnRatePerDay: burnRatePerDay,
      inbound: inbound,
      today: today,
    );

    final orderBy = leadDays != null
        ? orderByDate(
            stockOutDate: projection.stockOutDate,
            effectiveLeadDays: leadDays,
            safetyStockDays: material.safetyStockDays,
          )
        : null;

    final risk = riskFor(
      orderByDate: orderBy,
      stockOutDate: projection.stockOutDate,
      today: today,
      hasSupplier: supplier != null,
    );

    final suggested = leadDays != null
        ? suggestedQty(
            burnRatePerDay: burnRatePerDay,
            onHand: material.currentStock,
            inboundTotal: _inboundWithinCoverWindow(
              inbound: inbound,
              startOfToday: startOfToday,
              effectiveLeadDays: leadDays,
              safetyStockDays: material.safetyStockDays,
            ),
            effectiveLeadDays: leadDays,
            safetyStockDays: material.safetyStockDays,
          )
        : null;

    return MaterialPlan(
      material: material,
      burnRatePerDay: burnRatePerDay,
      onHand: material.currentStock,
      inboundTotal: inboundTotal,
      overdueInboundTotal: overdueInboundTotal,
      overdueOrderCount: overdueOrders.length,
      bestSupplier: supplier,
      effectiveLeadDays: leadDays,
      daysOfCover: projection.daysOfCover,
      stockOutDate: projection.stockOutDate,
      orderByDate: orderBy,
      suggestedQty: suggested,
      risk: risk,
      reorderLevel: reorderLevel,
      belowReorderLevel: material.currentStock <= reorderLevel,
      dailyBalances: projection.dailyBalances,
    );
  }

  static double? onTimeRate(Iterable<PurchaseOrder> orders) {
    final withData = orders
        .where(
          (o) =>
              o.status == PurchaseOrderStatus.delivered &&
              o.deliveredAt != null &&
              o.expectedDelivery != null,
        )
        .toList();
    if (withData.length < 3) return null;
    final onTime = withData.where(
      (o) => !o.deliveredAt!.isAfter(o.expectedDelivery!),
    );
    return onTime.length / withData.length;
  }

  static double? suggestedRating(double? onTimeRate) {
    if (onTimeRate == null) return null;
    return (onTimeRate * 5).clamp(0, 5);
  }

  static List<SupplierComparison> compareSuppliers({
    required List<Supplier> suppliersForMaterial,
    required List<PurchaseOrder> historyForMaterial,
  }) {
    if (suppliersForMaterial.isEmpty) return [];
    final recommended = bestSupplier(suppliersForMaterial);

    final rows = suppliersForMaterial.map((supplier) {
      final history = historyForMaterial
          .where((o) => o.supplierId == supplier.supplierId)
          .toList();
      final rate = onTimeRate(history);
      final lead = effectiveLeadDays(supplier);
      final price = latestUnitPrice(history);
      final isRecommended =
          recommended != null && supplier.supplierId == recommended.supplierId;

      var reason = '';
      if (isRecommended) {
        final rateText = rate != null
            ? 'on-time rate ${(rate * 100).round()}%'
            : 'not enough delivery history yet';
        reason = 'Shortest effective lead time ($lead d), $rateText';
      }

      return SupplierComparison(
        supplier: supplier,
        quotedLeadDays: supplier.leadTimeDays,
        effectiveLeadDays: lead,
        reliabilityRating: supplier.reliabilityRating,
        onTimeRate: rate,
        historyCount: history.length,
        unitPrice: price,
        isRecommended: isRecommended,
        reason: reason,
      );
    }).toList();

    rows.sort((a, b) {
      final lead = a.effectiveLeadDays.compareTo(b.effectiveLeadDays);
      if (lead != 0) return lead;
      final ap = a.unitPrice;
      final bp = b.unitPrice;
      if (ap != null && bp != null && ap != bp) return ap.compareTo(bp);
      if (ap == null && bp != null) return 1;
      if (ap != null && bp == null) return -1;
      return b.reliabilityRating.compareTo(a.reliabilityRating);
    });
    return rows;
  }
}
