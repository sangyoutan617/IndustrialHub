import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/demand_forecast.dart';
import 'package:industrial_hub/models/purchase_order.dart';
import 'package:industrial_hub/models/raw_material.dart';
import 'package:industrial_hub/models/supplier.dart';
import 'package:industrial_hub/services/capacity_service.dart';
import 'package:industrial_hub/services/mrp_service.dart';
import 'package:industrial_hub/services/supply_service.dart';

RawMaterial _material({
  double currentStock = 100,
  double consumptionPerUnit = 1,
  double reorderLevel = 0,
  int safetyStockDays = 3,
}) {
  return RawMaterial(
    materialId: 1,
    factoryId: 1,
    materialName: 'Test material',
    currentStock: currentStock,
    unit: 'kg',
    consumptionPerUnit: consumptionPerUnit,
    reorderLevel: reorderLevel,
    safetyStockDays: safetyStockDays,
  );
}

Supplier _supplier({
  int supplierId = 1,
  int leadTimeDays = 7,
  double reliabilityRating = 5,
}) {
  return Supplier(
    supplierId: supplierId,
    supplierName: 'Test supplier $supplierId',
    materialId: 1,
    leadTimeDays: leadTimeDays,
    reliabilityRating: reliabilityRating,
    isSimulated: false,
  );
}

PurchaseOrder _order({
  int poId = 1,
  int supplierId = 1,
  double quantity = 100,
  required DateTime orderDate,
  DateTime? expectedDelivery,
  DateTime? deliveredAt,
  String status = PurchaseOrderStatus.pending,
}) {
  return PurchaseOrder(
    poId: poId,
    supplierId: supplierId,
    materialId: 1,
    quantity: quantity,
    orderDate: orderDate,
    expectedDelivery: expectedDelivery,
    deliveredAt: deliveredAt,
    status: status,
    isSimulated: false,
  );
}

MaterialPlan _plan({required SupplyRisk risk, bool belowReorderLevel = false}) {
  return MaterialPlan(
    material: _material(),
    burnRatePerDay: 0,
    onHand: 0,
    inboundTotal: 0,
    overdueInboundTotal: 0,
    overdueOrderCount: 0,
    bestSupplier: null,
    effectiveLeadDays: null,
    daysOfCover: null,
    stockOutDate: null,
    orderByDate: null,
    suggestedQty: null,
    risk: risk,
    belowReorderLevel: belowReorderLevel,
    dailyBalances: const [],
  );
}

CapacitySnapshot _snapshot(double effectiveCapacity) {
  return CapacitySnapshot(
    machines: const [],
    shifts: const [],
    machineCapacity: effectiveCapacity,
    manpowerCapacity: effectiveCapacity,
    effectiveCapacity: effectiveCapacity,
    bottleneckResource: 'MACHINE',
  );
}

DemandForecast _forecast({int requiredPerDay = 100}) {
  return DemandForecast(
    demandId: 1,
    factoryId: 1,
    productName: 'Test product',
    requiredPerDay: requiredPerDay,
  );
}

void main() {
  final today = DateTime(2026, 1, 1);

  group('MrpService.project', () {
    test('predicts an exact stock-out day with no inbound deliveries', () {
      final projection = MrpService.project(
        openingStock: 100,
        burnRatePerDay: 10,
        inbound: const [],
        today: today,
      );
      expect(projection.stockOutDate, today.add(const Duration(days: 10)));
      expect(projection.daysOfCover, 10);
    });

    test('an inbound delivery pushes the stock-out date later', () {
      final baseline = MrpService.project(
        openingStock: 100,
        burnRatePerDay: 10,
        inbound: const [],
        today: today,
      );
      final withInbound = MrpService.project(
        openingStock: 100,
        burnRatePerDay: 10,
        inbound: [InboundDelivery(today.add(const Duration(days: 5)), 60)],
        today: today,
      );
      expect(
        withInbound.stockOutDate!.isAfter(baseline.stockOutDate!),
        isTrue,
      );
    });

    test('an overdue-but-still-open delivery still counts toward cover '
        '(folded onto day 0, not silently dropped)', () {
      final baseline = MrpService.project(
        openingStock: 50,
        burnRatePerDay: 10,
        inbound: const [],
        today: today,
      );
      // This order's date is 3 days in the past — it hasn't been marked
      // delivered/cancelled yet, so it's still expected, just late.
      final withOverdueInbound = MrpService.project(
        openingStock: 50,
        burnRatePerDay: 10,
        inbound: [
          InboundDelivery(today.subtract(const Duration(days: 3)), 100),
        ],
        today: today,
      );
      expect(
        withOverdueInbound.stockOutDate!.isAfter(baseline.stockOutDate!),
        isTrue,
        reason:
            'an overdue open PO must still push the stock-out date out — '
            'its quantity cannot just vanish from the projection',
      );
    });

    test('returns null stock-out when inbound covers the whole horizon', () {
      final projection = MrpService.project(
        openingStock: 0,
        burnRatePerDay: 10,
        inbound: [InboundDelivery(today, 100000)],
        today: today,
        horizonDays: 30,
      );
      expect(projection.stockOutDate, isNull);
      expect(projection.daysOfCover, isNull);
    });

    test('a zero burn rate never depletes the balance', () {
      final projection = MrpService.project(
        openingStock: 5,
        burnRatePerDay: 0,
        inbound: const [],
        today: today,
        horizonDays: 10,
      );
      expect(projection.stockOutDate, isNull);
      expect(projection.daysOfCover, isNull);
      expect(projection.dailyBalances, everyElement(5));
    });

    test('multiple deliveries landing on the same day are summed', () {
      final projection = MrpService.project(
        openingStock: 0,
        burnRatePerDay: 1,
        inbound: [
          InboundDelivery(today.add(const Duration(days: 2)), 10),
          InboundDelivery(today.add(const Duration(days: 2)), 5),
        ],
        today: today,
        horizonDays: 5,
      );
      // Day 2: balance before this day's delivery is 0-1-1 = -2, then
      // +15 arrives, then -1 burn => 12.
      expect(projection.dailyBalances[2], 12);
    });

    test('walks exactly horizonDays + 1 entries (today through the last '
        'day of the horizon, inclusive)', () {
      final projection = MrpService.project(
        openingStock: 1000,
        burnRatePerDay: 1,
        inbound: const [],
        today: today,
        horizonDays: 30,
      );
      expect(projection.dailyBalances, hasLength(31));
    });
  });

  group('MrpService.effectiveLeadDays', () {
    test('a 5-star supplier keeps its quoted lead time', () {
      expect(
        MrpService.effectiveLeadDays(
          _supplier(leadTimeDays: 10, reliabilityRating: 5),
        ),
        10,
      );
    });

    test('a 0-star supplier gets +50% padding', () {
      expect(
        MrpService.effectiveLeadDays(
          _supplier(leadTimeDays: 10, reliabilityRating: 0),
        ),
        15,
      );
    });

    test('a 2.5-star supplier gets +25% padding', () {
      expect(
        MrpService.effectiveLeadDays(
          _supplier(leadTimeDays: 8, reliabilityRating: 2.5),
        ),
        10,
      );
    });
  });

  group('MrpService.bestSupplier', () {
    test('prefers a slower-quoted but reliable supplier over a faster '
        'but unreliable one', () {
      final fastButUnreliable = _supplier(
        supplierId: 1,
        leadTimeDays: 5,
        reliabilityRating: 0,
      ); // effective 8 days
      final slowerButReliable = _supplier(
        supplierId: 2,
        leadTimeDays: 7,
        reliabilityRating: 5,
      ); // effective 7 days
      final best = MrpService.bestSupplier([
        fastButUnreliable,
        slowerButReliable,
      ]);
      expect(best!.supplierId, 2);
    });

    test('returns null for an empty supplier list', () {
      expect(MrpService.bestSupplier(const []), isNull);
    });

    test('breaks a tie on equal effective lead time in favour of the '
        'higher-rated supplier', () {
      final fiveStar = _supplier(
        supplierId: 1,
        leadTimeDays: 10,
        reliabilityRating: 5,
      ); // effective 10 days
      final twoPointFiveStar = _supplier(
        supplierId: 2,
        leadTimeDays: 8,
        reliabilityRating: 2.5,
      ); // effective 10 days too (8 * 1.25) — same as above, tie
      final best = MrpService.bestSupplier([fiveStar, twoPointFiveStar]);
      expect(best!.supplierId, 1);
    });
  });

  group('MrpService.riskFor / orderByDate', () {
    test('an order-by date exactly today is reorderNow', () {
      final risk = MrpService.riskFor(
        orderByDate: today,
        stockOutDate: today.add(const Duration(days: 10)),
        today: today,
        hasSupplier: true,
      );
      expect(risk, SupplyRisk.reorderNow);
    });

    test('an order-by date within the watch window is watch', () {
      final risk = MrpService.riskFor(
        orderByDate: today.add(const Duration(days: 5)),
        stockOutDate: today.add(const Duration(days: 20)),
        today: today,
        hasSupplier: true,
      );
      expect(risk, SupplyRisk.watch);
    });

    test('a stock-out today or earlier is stockedOut regardless of '
        'order-by date', () {
      final risk = MrpService.riskFor(
        orderByDate: today.add(const Duration(days: 5)),
        stockOutDate: today,
        today: today,
        hasSupplier: true,
      );
      expect(risk, SupplyRisk.stockedOut);
    });

    test('no supplier means no lead time to plan against', () {
      final risk = MrpService.riskFor(
        orderByDate: null,
        stockOutDate: today.add(const Duration(days: 10)),
        today: today,
        hasSupplier: false,
      );
      expect(risk, SupplyRisk.noSupplier);
    });

    test('a comfortable order-by date is healthy', () {
      final risk = MrpService.riskFor(
        orderByDate: today.add(const Duration(days: 30)),
        stockOutDate: today.add(const Duration(days: 60)),
        today: today,
        hasSupplier: true,
      );
      expect(risk, SupplyRisk.healthy);
    });

    test('orderByDate subtracts effective lead time and safety stock from '
        'the stock-out date', () {
      final orderBy = MrpService.orderByDate(
        stockOutDate: today.add(const Duration(days: 10)),
        effectiveLeadDays: 7,
        safetyStockDays: 3,
      );
      expect(orderBy, today);
    });

    test('orderByDate is null when there is no projected stock-out', () {
      expect(
        MrpService.orderByDate(
          stockOutDate: null,
          effectiveLeadDays: 7,
          safetyStockDays: 3,
        ),
        isNull,
      );
    });

    test('has a supplier but no order-by date (no projected stock-out) is '
        'healthy, not watch or reorderNow', () {
      final risk = MrpService.riskFor(
        orderByDate: null,
        stockOutDate: null,
        today: today,
        hasSupplier: true,
      );
      expect(risk, SupplyRisk.healthy);
    });

    test('an order-by date exactly watchWindowDays away is still watch '
        '(boundary is inclusive)', () {
      final risk = MrpService.riskFor(
        orderByDate: today.add(Duration(days: MrpService.watchWindowDays)),
        stockOutDate: today.add(const Duration(days: 30)),
        today: today,
        hasSupplier: true,
      );
      expect(risk, SupplyRisk.watch);
    });

    test('an order-by date one day past the watch window is healthy', () {
      final risk = MrpService.riskFor(
        orderByDate: today.add(
          Duration(days: MrpService.watchWindowDays + 1),
        ),
        stockOutDate: today.add(const Duration(days: 30)),
        today: today,
        hasSupplier: true,
      );
      expect(risk, SupplyRisk.healthy);
    });
  });

  group('MrpService.suggestedQty', () {
    test('covers lead time + safety stock + review period, net of on-hand '
        'and inbound', () {
      final qty = MrpService.suggestedQty(
        burnRatePerDay: 10,
        onHand: 50,
        inboundTotal: 20,
        effectiveLeadDays: 7,
        safetyStockDays: 3,
      );
      // targetCoverDays = 7 + 3 + 14 = 24; raw = 240 - 50 - 20 = 170
      expect(qty, 170);
    });

    test('never goes negative when on-hand already covers the target', () {
      final qty = MrpService.suggestedQty(
        burnRatePerDay: 10,
        onHand: 10000,
        inboundTotal: 0,
        effectiveLeadDays: 7,
        safetyStockDays: 3,
      );
      expect(qty, 0);
    });

    test('rounds a non-multiple-of-10 raw amount up to the next 10', () {
      final qty = MrpService.suggestedQty(
        burnRatePerDay: 10,
        onHand: 49,
        inboundTotal: 0,
        effectiveLeadDays: 7,
        safetyStockDays: 3,
      );
      // targetCoverDays = 24; raw = 240 - 49 = 191 -> rounds up to 200,
      // not truncated to 190.
      expect(qty, 200);
    });
  });

  group('MrpService.buildPlan', () {
    test('belowReorderLevel triggers independently of date logic even '
        'with no supplier at all', () {
      final plan = MrpService.buildPlan(
        material: _material(currentStock: 5, reorderLevel: 10),
        suppliersForMaterial: const [],
        ordersForMaterial: const [],
        plannedProductionPerDay: 10,
        today: today,
      );
      expect(plan.belowReorderLevel, isTrue);
      expect(plan.risk, SupplyRisk.noSupplier);
      // No supplier means no lead time, so neither of these can be
      // computed at all — they must stay null, not default to 0.
      expect(plan.suggestedQty, isNull);
      expect(plan.orderByDate, isNull);
    });

    test('burn rate is consumption per unit times planned production', () {
      final plan = MrpService.buildPlan(
        material: _material(consumptionPerUnit: 3),
        suppliersForMaterial: [_supplier()],
        ordersForMaterial: const [],
        plannedProductionPerDay: 20,
        today: today,
      );
      expect(plan.burnRatePerDay, 60);
    });

    test('an open purchase order pushes the stock-out date later than with '
        'no orders at all', () {
      final material = _material(currentStock: 50, consumptionPerUnit: 1);
      final supplier = _supplier(leadTimeDays: 5);
      final baseline = MrpService.buildPlan(
        material: material,
        suppliersForMaterial: [supplier],
        ordersForMaterial: const [],
        plannedProductionPerDay: 10,
        today: today,
      );
      final withOrder = MrpService.buildPlan(
        material: material,
        suppliersForMaterial: [supplier],
        ordersForMaterial: [
          _order(
            orderDate: today,
            expectedDelivery: today.add(const Duration(days: 2)),
            quantity: 200,
            status: PurchaseOrderStatus.processing,
          ),
        ],
        plannedProductionPerDay: 10,
        today: today,
      );
      expect(withOrder.inboundTotal, 200);
      expect(
        withOrder.stockOutDate!.isAfter(baseline.stockOutDate!),
        isTrue,
      );
    });

    test('delivered and cancelled orders are excluded from inbound — their '
        'stock is already reflected in current_stock', () {
      final plan = MrpService.buildPlan(
        material: _material(currentStock: 50, consumptionPerUnit: 1),
        suppliersForMaterial: [_supplier()],
        ordersForMaterial: [
          _order(
            poId: 1,
            orderDate: today.subtract(const Duration(days: 10)),
            expectedDelivery: today.subtract(const Duration(days: 5)),
            quantity: 1000,
            status: PurchaseOrderStatus.delivered,
          ),
          _order(
            poId: 2,
            orderDate: today,
            expectedDelivery: today.add(const Duration(days: 1)),
            quantity: 500,
            status: PurchaseOrderStatus.cancelled,
          ),
        ],
        plannedProductionPerDay: 10,
        today: today,
      );
      expect(plan.inboundTotal, 0);
    });

    test('overdueInboundTotal and overdueOrderCount only count open orders '
        'whose expected delivery has already passed', () {
      final plan = MrpService.buildPlan(
        material: _material(currentStock: 50, consumptionPerUnit: 1),
        suppliersForMaterial: [_supplier()],
        ordersForMaterial: [
          _order(
            poId: 1,
            orderDate: today.subtract(const Duration(days: 10)),
            expectedDelivery: today.subtract(const Duration(days: 3)),
            quantity: 300,
            status: PurchaseOrderStatus.shipped,
          ),
          _order(
            poId: 2,
            orderDate: today,
            expectedDelivery: today.add(const Duration(days: 2)),
            quantity: 400,
            status: PurchaseOrderStatus.pending,
          ),
        ],
        plannedProductionPerDay: 10,
        today: today,
      );
      expect(plan.overdueOrderCount, 1);
      expect(plan.overdueInboundTotal, 300);
      expect(plan.inboundTotal, 700);
    });

    test('a missing expected-delivery date falls back to the order\'s own '
        'supplier lead time, not the material\'s overall best supplier', () {
      final material = _material(currentStock: 100, consumptionPerUnit: 1);
      // The best supplier overall is fast (3-day effective lead)...
      final fastBestSupplier = _supplier(
        supplierId: 1,
        leadTimeDays: 3,
        reliabilityRating: 5,
      );
      // ...but this particular order was placed with a slower supplier,
      // and never got an expected-delivery date recorded.
      final slowOrderSupplier = _supplier(
        supplierId: 2,
        leadTimeDays: 10,
        reliabilityRating: 5,
      );
      final plan = MrpService.buildPlan(
        material: material,
        suppliersForMaterial: [fastBestSupplier, slowOrderSupplier],
        ordersForMaterial: [
          _order(
            supplierId: 2,
            orderDate: today,
            expectedDelivery: null,
            quantity: 1000,
            status: PurchaseOrderStatus.pending,
          ),
        ],
        plannedProductionPerDay: 1,
        today: today,
      );
      // Days 0-9: no inbound yet, balance just drains by 1/day from 100.
      expect(plan.dailyBalances[9], 90);
      // Day 10: the order's own (slow) supplier's lead time — this is
      // when the 1000 units should land, not on day 3.
      expect(plan.dailyBalances[10], greaterThan(1000));
    });
  });

  group('MrpService.onTimeRate', () {
    test('returns null with fewer than 3 delivered orders on record', () {
      final orders = [
        _order(
          orderDate: today,
          expectedDelivery: today.add(const Duration(days: 5)),
          deliveredAt: today.add(const Duration(days: 4)),
          status: PurchaseOrderStatus.delivered,
        ),
        _order(
          orderDate: today,
          expectedDelivery: today.add(const Duration(days: 5)),
          deliveredAt: today.add(const Duration(days: 4)),
          status: PurchaseOrderStatus.delivered,
        ),
      ];
      expect(MrpService.onTimeRate(orders), isNull);
    });

    test('computes the fraction delivered on or before the expected date', () {
      final expected = today.add(const Duration(days: 5));
      final orders = [
        _order(
          orderDate: today,
          expectedDelivery: expected,
          deliveredAt: expected.subtract(const Duration(days: 1)), // on time
          status: PurchaseOrderStatus.delivered,
        ),
        _order(
          orderDate: today,
          expectedDelivery: expected,
          deliveredAt: expected, // on time
          status: PurchaseOrderStatus.delivered,
        ),
        _order(
          orderDate: today,
          expectedDelivery: expected,
          deliveredAt: expected.add(const Duration(days: 2)), // late
          status: PurchaseOrderStatus.delivered,
        ),
      ];
      expect(MrpService.onTimeRate(orders), closeTo(2 / 3, 0.0001));
    });

    test('excludes orders that aren\'t delivered, or are missing either '
        'date, even when there are enough of them to otherwise pass the '
        'minimum-sample check', () {
      final expected = today.add(const Duration(days: 5));
      final orders = [
        // Delivered, both dates present — counts.
        _order(
          orderDate: today,
          expectedDelivery: expected,
          deliveredAt: expected,
          status: PurchaseOrderStatus.delivered,
        ),
        // Delivered, both dates present — counts.
        _order(
          orderDate: today,
          expectedDelivery: expected,
          deliveredAt: expected,
          status: PurchaseOrderStatus.delivered,
        ),
        // Still shipped, not delivered yet — excluded even though
        // deliveredAt happens to be unset here too.
        _order(
          orderDate: today,
          expectedDelivery: expected,
          status: PurchaseOrderStatus.shipped,
        ),
        // Delivered but never got an expected-delivery date — excluded.
        _order(
          orderDate: today,
          expectedDelivery: null,
          deliveredAt: expected,
          status: PurchaseOrderStatus.delivered,
        ),
      ];
      // Only 2 orders qualify, below the minimum sample of 3.
      expect(MrpService.onTimeRate(orders), isNull);
    });
  });

  group('MrpService.compareSuppliers', () {
    test('recommends the same supplier bestSupplier would pick', () {
      final fastButUnreliable = _supplier(
        supplierId: 1,
        leadTimeDays: 5,
        reliabilityRating: 0,
      );
      final slowerButReliable = _supplier(
        supplierId: 2,
        leadTimeDays: 7,
        reliabilityRating: 5,
      );
      final comparisons = MrpService.compareSuppliers(
        suppliersForMaterial: [fastButUnreliable, slowerButReliable],
        historyForMaterial: const [],
      );
      final recommended = comparisons.where((c) => c.isRecommended).toList();
      expect(recommended, hasLength(1));
      expect(recommended.first.supplier.supplierId, 2);
    });

    test('returns an empty list when no suppliers exist', () {
      expect(
        MrpService.compareSuppliers(
          suppliersForMaterial: const [],
          historyForMaterial: const [],
        ),
        isEmpty,
      );
    });

    test('sorts rows by effective lead time, fastest first', () {
      final slow = _supplier(supplierId: 1, leadTimeDays: 20);
      final fast = _supplier(supplierId: 2, leadTimeDays: 3);
      final medium = _supplier(supplierId: 3, leadTimeDays: 10);
      final comparisons = MrpService.compareSuppliers(
        suppliersForMaterial: [slow, fast, medium],
        historyForMaterial: const [],
      );
      expect(
        comparisons.map((c) => c.supplier.supplierId).toList(),
        [2, 3, 1],
      );
    });

    test('partitions delivery history by supplier — each row\'s on-time '
        'rate and history count reflect only its own orders', () {
      final supplierA = _supplier(supplierId: 1, leadTimeDays: 5);
      final supplierB = _supplier(supplierId: 2, leadTimeDays: 5);
      final expected = today.add(const Duration(days: 5));
      final history = [
        // 3 on-time deliveries for supplier A.
        for (var i = 0; i < 3; i++)
          _order(
            poId: i,
            supplierId: 1,
            orderDate: today,
            expectedDelivery: expected,
            deliveredAt: expected,
            status: PurchaseOrderStatus.delivered,
          ),
        // Only 1 delivery on record for supplier B — below the minimum
        // sample, so its on-time rate must stay null.
        _order(
          poId: 100,
          supplierId: 2,
          orderDate: today,
          expectedDelivery: expected,
          deliveredAt: expected,
          status: PurchaseOrderStatus.delivered,
        ),
      ];
      final comparisons = MrpService.compareSuppliers(
        suppliersForMaterial: [supplierA, supplierB],
        historyForMaterial: history,
      );
      final rowA = comparisons.firstWhere((c) => c.supplier.supplierId == 1);
      final rowB = comparisons.firstWhere((c) => c.supplier.supplierId == 2);
      expect(rowA.historyCount, 3);
      expect(rowA.onTimeRate, 1.0);
      expect(rowB.historyCount, 1);
      expect(rowB.onTimeRate, isNull);
    });

    test('the recommended row explains itself with delivery history; a '
        'recommendation with no history yet says so instead', () {
      final onlySupplier = _supplier(supplierId: 1, leadTimeDays: 5);
      final withHistory = MrpService.compareSuppliers(
        suppliersForMaterial: [onlySupplier],
        historyForMaterial: [
          for (var i = 0; i < 3; i++)
            _order(
              poId: i,
              supplierId: 1,
              orderDate: today,
              expectedDelivery: today.add(const Duration(days: 5)),
              deliveredAt: today.add(const Duration(days: 5)),
              status: PurchaseOrderStatus.delivered,
            ),
        ],
      );
      expect(withHistory.single.reason, contains('on-time rate'));

      final withoutHistory = MrpService.compareSuppliers(
        suppliersForMaterial: [onlySupplier],
        historyForMaterial: const [],
      );
      expect(withoutHistory.single.reason, contains('not enough delivery history'));
    });
  });

  group('MrpService.suggestedRating', () {
    test('passes through null when there is no on-time rate to convert', () {
      expect(MrpService.suggestedRating(null), isNull);
    });

    test('converts a fractional on-time rate onto a 5-star scale', () {
      expect(MrpService.suggestedRating(0.8), 4.0);
    });

    test('clamps to the 0-5 range', () {
      expect(MrpService.suggestedRating(1.0), 5.0);
      expect(MrpService.suggestedRating(0.0), 0.0);
    });
  });

  group('MaterialPlan.needsAttention', () {
    test('reorderNow, stockedOut, and watch all need attention', () {
      expect(_plan(risk: SupplyRisk.reorderNow).needsAttention, isTrue);
      expect(_plan(risk: SupplyRisk.stockedOut).needsAttention, isTrue);
      expect(_plan(risk: SupplyRisk.watch).needsAttention, isTrue);
    });

    test('healthy or noSupplier alone do not need attention', () {
      expect(_plan(risk: SupplyRisk.healthy).needsAttention, isFalse);
      expect(_plan(risk: SupplyRisk.noSupplier).needsAttention, isFalse);
    });

    test('belowReorderLevel forces attention even when risk is healthy', () {
      expect(
        _plan(
          risk: SupplyRisk.healthy,
          belowReorderLevel: true,
        ).needsAttention,
        isTrue,
      );
    });
  });

  group('PurchaseOrder.isClosed', () {
    test('delivered and cancelled orders are closed', () {
      expect(
        _order(
          orderDate: today,
          status: PurchaseOrderStatus.delivered,
        ).isClosed,
        isTrue,
      );
      expect(
        _order(
          orderDate: today,
          status: PurchaseOrderStatus.cancelled,
        ).isClosed,
        isTrue,
      );
    });

    test('pending, processing, and shipped orders are still open', () {
      expect(
        _order(
          orderDate: today,
          status: PurchaseOrderStatus.pending,
        ).isClosed,
        isFalse,
      );
      expect(
        _order(
          orderDate: today,
          status: PurchaseOrderStatus.processing,
        ).isClosed,
        isFalse,
      );
      expect(
        _order(
          orderDate: today,
          status: PurchaseOrderStatus.shipped,
        ).isClosed,
        isFalse,
      );
    });
  });

  group('SupplyService.plannedProductionPerDayFor', () {
    test('falls back to full capacity when there is no demand forecast', () {
      final result = SupplyService.plannedProductionPerDayFor(
        _snapshot(500),
        const [],
      );
      expect(result, 500);
    });

    test('caps the forecast total at effective capacity', () {
      final result = SupplyService.plannedProductionPerDayFor(_snapshot(500), [
        _forecast(requiredPerDay: 800),
      ]);
      expect(result, 500);
    });

    test('uses the forecast total when it fits within capacity', () {
      final result = SupplyService.plannedProductionPerDayFor(_snapshot(500), [
        _forecast(requiredPerDay: 300),
      ]);
      expect(result, 300);
    });

    test('is 0 when there is no capacity data and no forecast (nothing to '
        'plan production against at all)', () {
      final result = SupplyService.plannedProductionPerDayFor(
        _snapshot(0),
        const [],
      );
      expect(result, 0);
    });
  });
}
