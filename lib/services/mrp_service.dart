import '../models/purchase_order.dart';
import '../models/raw_material.dart';
import '../models/supplier.dart';

/// A single incoming quantity landing on a known date — built from open
/// purchase orders and fed into [MrpService.project].
class InboundDelivery {
  final DateTime date;
  final double quantity;

  const InboundDelivery(this.date, this.quantity);
}

/// Result of walking the stock balance forward day by day.
class MrpProjection {
  /// First day the projected balance goes negative, or null when the
  /// balance stays non-negative through the whole horizon.
  final DateTime? stockOutDate;

  /// Projected end-of-day balance for each day in the horizon, index 0
  /// being today. Used to draw the stock projection chart.
  final List<double> dailyBalances;

  /// Days from today until [stockOutDate]. Null when there is no burn
  /// rate to project against, or the horizon was exhausted without a
  /// stock-out — callers should render that as "{horizon}+ days".
  final double? daysOfCover;

  const MrpProjection({
    required this.stockOutDate,
    required this.dailyBalances,
    required this.daysOfCover,
  });
}

/// How urgent it is to act on a material right now.
enum SupplyRisk {
  /// Comfortably covered.
  healthy,

  /// The order-by date is coming up within the watch window.
  watch,

  /// Past the last safe moment to place an order — the supplier's lead
  /// time no longer fits before the projected stock-out.
  reorderNow,

  /// Already projected to be out of stock today or earlier.
  stockedOut,

  /// No supplier is linked, so no lead time — and therefore no
  /// order-by date — can be computed at all.
  noSupplier,
}

/// The full Mini-MRP read-out for one material: burn rate, inbound
/// coverage, predicted stock-out date, and the latest safe reorder date.
class MaterialPlan {
  final RawMaterial material;
  final double burnRatePerDay;
  final double onHand;
  final double inboundTotal;

  /// Portion of [inboundTotal] that's already past its expected delivery
  /// date but still open (not delivered/cancelled) — still counted toward
  /// cover, but worth flagging since the projection is relying on a
  /// shipment that's running late.
  final double overdueInboundTotal;
  final int overdueOrderCount;
  final Supplier? bestSupplier;
  final int? effectiveLeadDays;
  final double? daysOfCover;
  final DateTime? stockOutDate;
  final DateTime? orderByDate;
  final double? suggestedQty;
  final SupplyRisk risk;
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
    required this.belowReorderLevel,
    required this.dailyBalances,
  });

  bool get needsAttention =>
      risk == SupplyRisk.reorderNow ||
      risk == SupplyRisk.stockedOut ||
      risk == SupplyRisk.watch ||
      belowReorderLevel;
}

/// One supplier's stats for a material, side by side with the others —
/// backs the supplier comparison screen.
class SupplierComparison {
  final Supplier supplier;
  final int quotedLeadDays;
  final int effectiveLeadDays;
  final double reliabilityRating;
  final double? onTimeRate;
  final int historyCount;
  final bool isRecommended;
  final String reason;

  const SupplierComparison({
    required this.supplier,
    required this.quotedLeadDays,
    required this.effectiveLeadDays,
    required this.reliabilityRating,
    required this.onTimeRate,
    required this.historyCount,
    required this.isRecommended,
    required this.reason,
  });
}

/// Pure Mini-MRP calculations: no Supabase, no widgets, fully unit-testable.
///
/// Mirrors the static-pure-function style already used by
/// `CapacityService.computeMachineCapacity` etc.
class MrpService {
  /// Extra days of cover targeted beyond lead time + safety stock when
  /// suggesting a reorder quantity, so a fresh order doesn't run out
  /// again the moment it lands.
  static const int reviewPeriodDays = 14;

  static const int defaultHorizonDays = 180;

  /// Order-by dates inside this many days from today are flagged as
  /// "watch" rather than "healthy".
  static const int watchWindowDays = 7;

  const MrpService._();

  /// A 5★ supplier is trusted to hit its quoted lead time. Padding scales
  /// linearly up to +50% for a 0★ supplier, so an unreliable supplier's
  /// deliveries are planned for later than they're quoted.
  static int effectiveLeadDays(Supplier supplier) {
    final ratingGap = (5 - supplier.reliabilityRating).clamp(0, 5);
    final factor = 1 + 0.5 * (ratingGap / 5);
    return (supplier.leadTimeDays * factor).ceil();
  }

  /// Picks the supplier with the lowest effective (reliability-adjusted)
  /// lead time, breaking ties in favour of the higher-rated supplier.
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

  /// Walks the stock balance forward one day at a time: add anything
  /// arriving that day, then subtract the daily burn rate. The first day
  /// the balance goes negative is the predicted stock-out date.
  ///
  /// A delivery dated before [today] (an order that's still open but
  /// running late) is folded onto day 0 rather than dropped — it's still
  /// expected, just overdue, so its quantity must still count toward
  /// cover instead of silently vanishing from the projection.
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

    // Built from today's year/month/day rather than Duration arithmetic so
    // a horizon that crosses a daylight-saving transition still lands on
    // local midnight each day and keeps matching the keys built above.
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

  /// The latest date an order can still be placed and land before the
  /// predicted stock-out, after reserving the safety-stock buffer.
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

  /// How much to order so stock lasts through lead time + safety stock +
  /// a review period, net of what's already on hand or inbound. Rounded
  /// up to the nearest 10 so the suggestion reads as a sensible order
  /// quantity rather than a jagged decimal.
  ///
  /// [inboundTotal] here should only include deliveries expected to land
  /// within the target cover window (lead time + safety stock + review
  /// period) — a shipment arriving well beyond that window doesn't cover
  /// today's shortfall, so it must not offset it. See [buildPlan], which
  /// computes that windowed figure and is the only real caller.
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

  /// Sum of [inbound] deliveries dated on or before the target cover
  /// window (lead time + safety stock + review period) from today —
  /// the boundary day itself still counts. Feeds [suggestedQty]; see its
  /// doc comment for why the window matters.
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

  /// Builds the full read-out for one material: burn rate from planned
  /// production, the best available supplier, an inbound-aware stock-out
  /// projection, and the derived order-by date / risk / suggested quantity.
  static MaterialPlan buildPlan({
    required RawMaterial material,
    required List<Supplier> suppliersForMaterial,
    required List<PurchaseOrder> ordersForMaterial,
    required double plannedProductionPerDay,
    required DateTime today,
  }) {
    final burnRate = material.consumptionPerUnit * plannedProductionPerDay;
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
      // Fall back to the order's own supplier's effective lead time (not
      // the material's overall best supplier) when no expected-delivery
      // date was recorded.
      final orderSupplier = suppliersById[order.supplierId];
      final fallbackLeadDays = orderSupplier != null
          ? effectiveLeadDays(orderSupplier)
          : (leadDays ?? 0);
      final date =
          order.expectedDelivery ??
          order.orderDate.add(Duration(days: fallbackLeadDays));
      return InboundDelivery(date, order.quantity);
    }).toList();

    // Still open, but the delivery date it was tracked against has already
    // passed — [project] folds these onto today rather than dropping them,
    // but the UI should still be able to flag that the read-out leans on a
    // late shipment.
    final overdueOrders = inbound
        .where((delivery) => delivery.date.isBefore(startOfToday))
        .toList();
    final overdueInboundTotal = overdueOrders.fold<double>(
      0,
      (sum, d) => sum + d.quantity,
    );

    final projection = project(
      openingStock: material.currentStock,
      burnRatePerDay: burnRate,
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
            burnRatePerDay: burnRate,
            onHand: material.currentStock,
            // Only count deliveries landing within the target cover window
            // — a shipment arriving well after that window doesn't help
            // cover the shortfall being sized right now, so it must not
            // suppress the suggestion (unlike `inboundTotal` above, which
            // is the full in-flight figure shown to the user as-is).
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
      burnRatePerDay: burnRate,
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
      belowReorderLevel: material.currentStock <= material.reorderLevel,
      dailyBalances: projection.dailyBalances,
    );
  }

  /// Fraction of delivered orders that arrived on or before their
  /// expected date. Returns null when there are fewer than 3 delivered
  /// orders with both dates recorded — too small a sample to trust.
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

  /// Converts an on-time rate into a suggested 5★ rating, so a manually
  /// entered rating can be compared against what the delivery history
  /// actually says.
  static double? suggestedRating(double? onTimeRate) {
    if (onTimeRate == null) return null;
    return (onTimeRate * 5).clamp(0, 5);
  }

  /// Side-by-side comparison of every supplier for one material: quoted
  /// vs effective lead time, reliability, on-time rate, and which one
  /// [bestSupplier] would actually pick.
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
        isRecommended: isRecommended,
        reason: reason,
      );
    }).toList();

    rows.sort((a, b) => a.effectiveLeadDays.compareTo(b.effectiveLeadDays));
    return rows;
  }
}
