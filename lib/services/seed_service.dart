import 'dart:math';

import '../models/bom_entry.dart';
import '../models/demand_forecast.dart';
import '../models/factory.dart';
import '../models/finished_stock.dart';
import '../models/machine.dart';
import '../models/manpower.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/raw_material.dart';
import '../models/raw_material_movement.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import 'bom_service.dart';
import 'capacity_service.dart';
import 'daily_production_service.dart';
import 'demand_service.dart';
import 'factory_service.dart';
import 'machine_downtime_service.dart';
import 'machine_service.dart';
import 'manpower_service.dart';
import 'material_movement_service.dart';
import 'material_service.dart';
import 'mrp_service.dart';
import 'order_service.dart';
import 'product_service.dart';
import 'stock_service.dart';
import 'supplier_service.dart';

enum SeedOutcome { created, alreadyExists }

class SeedResult {
  final SeedOutcome outcome;
  final Factory factory;

  const SeedResult(this.outcome, this.factory);
}

/// One scripted downtime event, used to build both the machine's own
/// downtime log and the day it happened's factory-level `downtime_hours`
/// figure — kept in one place so the two stay in sync rather than drifting
/// apart as separate magic numbers.
typedef _DowntimeEvent = ({
  int daysAgo,
  String machineName,
  double hours,
  String reason,
});

class SeedService {
  static const _demoFactoryName = 'Demo Beverage Factory';

  /// The product every seeded machine, shift, material recipe, stock row,
  /// and 90 days of history belongs to — a real factory's whole line is
  /// tied to what it actually makes, not to the auto-created "General"
  /// catch-all every factory also gets (left empty here, same as a real
  /// factory that hasn't reassigned its legacy data to a real product yet).
  static const _flagshipProductName = 'Sparkling Water 500ml';

  static const _historyDays = 90;

  /// Every downtime event in the demo's history. The last one is
  /// deliberately still open (no resolution here) — see
  /// [_seedDowntimeHistory], which is the one place that decides how each
  /// event is closed out.
  static final List<_DowntimeEvent> _downtimeEvents = [
    (
      daysAgo: 75,
      machineName: 'Extruder Line A',
      hours: 3.0,
      reason: 'Nozzle clog',
    ),
    (
      daysAgo: 52,
      machineName: 'Packaging Unit',
      hours: 2.0,
      reason: 'Conveyor belt slipped',
    ),
    (
      daysAgo: 30,
      machineName: 'Extruder Line A',
      hours: 6.0,
      reason: 'Scheduled maintenance',
    ),
    (
      daysAgo: 14,
      machineName: 'Packaging Unit',
      hours: 4.0,
      reason: 'Sensor fault',
    ),
    (
      daysAgo: 1,
      machineName: 'Extruder Line B',
      hours: 5.0,
      reason: 'Hydraulic pressure drop',
    ),
  ];

  final _factoryService = FactoryService();
  final _machineService = MachineService();
  final _manpowerService = ManpowerService();
  final _materialService = MaterialService();
  final _productService = ProductService();
  final _bomService = BomService();
  final _supplierService = SupplierService();
  final _stockService = StockService();
  final _demandService = DemandService();
  final _orderService = OrderService();
  final _dailyProductionService = DailyProductionService();
  final _downtimeService = MachineDowntimeService();
  final _movementService = MaterialMovementService();

  Future<SeedResult> seedDemoData() async {
    final existing = await _factoryService.getFactories();
    for (final factory in existing) {
      if (factory.factoryName == _demoFactoryName) {
        return SeedResult(SeedOutcome.alreadyExists, factory);
      }
    }

    final factory = await _seedFactory();
    final product = await _productService.createProduct(
      Product(
        productId: 0,
        factoryId: factory.factoryId,
        productName: _flagshipProductName,
        unit: 'bottles',
      ),
    );
    final machines = await _seedMachines(factory.factoryId, product.productId);
    final shifts = await _seedManpower(factory.factoryId, product.productId);
    final materials = await _seedMaterials(factory.factoryId, product.productId);
    final bom = await _bomService.getBom(product.productId);
    final suppliers = await _seedSuppliers(materials);
    final stock = await _stockService.createStock(factory.factoryId, product, 0);
    await _seedDemand(factory.factoryId, product);
    await _seedDowntimeHistory(factory.factoryId, machines);
    await _seedProductionAndConsumptionHistory(
      factoryId: factory.factoryId,
      productId: product.productId,
      shifts: shifts,
      materials: materials,
      bom: bom,
      stock: stock,
    );
    await _simulateOrders(factory.factoryId, materials, suppliers);

    return SeedResult(SeedOutcome.created, factory);
  }

  Future<Factory> _seedFactory() {
    return _factoryService.createFactory(
      _demoFactoryName,
      location: 'Shah Alam',
      state: 'Selangor',
      msicCode: '11',
    );
  }

  Future<List<Machine>> _seedMachines(int factoryId, int productId) async {
    final specs = [
      ('Extruder Line A', 50.0, 16.0, 'Active'),
      ('Extruder Line B', 40.0, 16.0, 'Active'),
      ('Packaging Unit', 100.0, 16.0, 'Active'),
      ('Old Mixer', 20.0, 8.0, 'Under Maintenance'),
    ];
    final created = <Machine>[];
    for (final (name, rated, hours, status) in specs) {
      created.add(
        await _machineService.createMachine(
          Machine(
            machineId: 0,
            factoryId: factoryId,
            productId: productId,
            machineName: name,
            ratedOutputPerHour: rated,
            operatingHoursPerDay: hours,
            status: status,
            isSimulated: true,
          ),
          isSimulated: true,
        ),
      );
    }
    return created;
  }

  Future<List<Manpower>> _seedManpower(int factoryId, int productId) async {
    final specs = [('Day Shift', 15, 8.0, 5.0), ('Night Shift', 8, 8.0, 4.0)];
    final created = <Manpower>[];
    for (final (name, workers, hours, perHour) in specs) {
      created.add(
        await _manpowerService.createShift(
          Manpower(
            manpowerId: 0,
            factoryId: factoryId,
            productId: productId,
            shiftName: name,
            workerCount: workers,
            shiftHours: hours,
            outputPerWorkerHour: perHour,
            isSimulated: true,
          ),
          isSimulated: true,
        ),
      );
    }
    return created;
  }

  /// [productId] receives each material's demo consumption rate as a
  /// product_materials (BOM) row. Rates are sized so 90 days of realistic
  /// output (see [_seedProductionAndConsumptionHistory]) draws each
  /// material's stock down gradually rather than instantly — enough to be
  /// worth replenishing partway through (see [_simulateOrders]) without
  /// ever needing to actually hit zero.
  Future<List<RawMaterial>> _seedMaterials(int factoryId, int productId) async {
    final specs = [
      ('Plastic Resin', 20000.0, 'kg', 0.25, 4.5),
      ('Colorant', 800.0, 'litres', 0.03, 12.0),
      ('Packaging Boxes', 10000.0, 'boxes', 0.12, 0.8),
    ];
    final created = <RawMaterial>[];
    for (final (name, stock, unit, quantityPerUnit, unitCost) in specs) {
      final material = await _materialService.createMaterial(
        RawMaterial(
          materialId: 0,
          factoryId: factoryId,
          materialName: name,
          currentStock: stock,
          unit: unit,
          unitCost: unitCost,
        ),
      );
      created.add(material);
      await _bomService.upsertEntry(
        BomEntry(
          productId: productId,
          materialId: material.materialId,
          quantityPerUnit: quantityPerUnit,
        ),
        factoryId: factoryId,
      );
    }
    return created;
  }

  Future<List<Supplier>> _seedSuppliers(List<RawMaterial> materials) async {
    final specs = {
      'Plastic Resin': (
        'Resin Supply Co',
        'Klang',
        5,
        4.2,
        'Lim Wei Sheng',
        '+60 3-3345 6789',
        'sales@resinsupply.com.my',
      ),
      'Colorant': (
        'ColorTech Industries',
        'Shah Alam',
        3,
        3.8,
        'Nurul Aina',
        '+60 3-5521 2345',
        'orders@colortech.com.my',
      ),
      'Packaging Boxes': (
        'PackRight Sdn Bhd',
        'Klang',
        10,
        4.7,
        'Ravi Kumar',
        '+60 3-3122 8899',
        'hello@packright.com.my',
      ),
    };
    final created = <Supplier>[];
    for (final material in materials) {
      final spec = specs[material.materialName];
      if (spec == null) continue;
      final (name, location, leadTime, rating, contact, phone, email) = spec;
      created.add(
        await _supplierService.createSupplier(
          Supplier(
            supplierId: 0,
            supplierName: name,
            location: location,
            materialId: material.materialId,
            leadTimeDays: leadTime,
            reliabilityRating: rating,
            isSimulated: true,
            contactPerson: contact,
            phone: phone,
            email: email,
          ),
          isSimulated: true,
        ),
      );
    }
    return created;
  }

  Future<void> _seedDemand(int factoryId, Product product) async {
    // Set a little above the factory's manpower-bound ceiling (856/day —
    // see _seedProductionAndConsumptionHistory) so the demo consistently
    // shows a modest, realistic shortfall rather than either comfortably
    // meeting demand every day or missing it by a wide margin.
    await _demandService.createForecast(
      DemandForecast(
        demandId: 0,
        factoryId: factoryId,
        productId: product.productId,
        productName: product.productName,
        requiredPerDay: 900,
      ),
    );
  }

  /// Writes every event in [_downtimeEvents]: every one but the last as an
  /// already-resolved historical entry (bulk-written directly, since
  /// [MachineDowntimeService]'s own start/mark-repaired calls stamp
  /// `DateTime.now()` — right for a live event, wrong for backfilling one
  /// from months ago), and the last one as a genuinely still-open event via
  /// [MachineDowntimeService.logDowntime] itself — the one machine this demo
  /// leaves mid-repair, so there's a live Start repair / Mark repaired
  /// action to walk through.
  Future<void> _seedDowntimeHistory(
    int factoryId,
    List<Machine> machines,
  ) async {
    final byName = {for (final m in machines) m.machineName: m};
    final now = DateTime.now();

    final resolved = _downtimeEvents.sublist(0, _downtimeEvents.length - 1);
    await _downtimeService.logHistoricalResolvedEvents(
      factoryId: factoryId,
      events: [
        for (final event in resolved)
          (
            machineId: byName[event.machineName]!.machineId,
            logDate: now.subtract(Duration(days: event.daysAgo)),
            hours: event.hours,
            reason: event.reason,
            repairStartedAt: now
                .subtract(Duration(days: event.daysAgo))
                .add(const Duration(hours: 1)),
            repairedAt: now
                .subtract(Duration(days: event.daysAgo))
                .add(Duration(hours: event.hours.round() + 2)),
          ),
      ],
    );

    final open = _downtimeEvents.last;
    await _downtimeService.logDowntime(
      machineId: byName[open.machineName]!.machineId,
      factoryId: factoryId,
      hours: open.hours,
      reason: open.reason,
      date: now.subtract(Duration(days: open.daysAgo)),
      isSimulated: true,
    );
  }

  /// The core of the demo: [_historyDays] (90 = roughly 3 months) of daily
  /// production, each day's raw-material consumption drawn straight from
  /// this product's own BOM (mirroring exactly what the real automatic-
  /// deduction path computes — see MrpService.computeProductionConsumption),
  /// a matching finished-goods ledger, and a handful of restocking
  /// deliveries so materials never actually run dry. All the heavy DB
  /// writes are batched (see the `logHistoricalBatch`/`recordBulkMovements`
  /// methods this calls) — 90 individual round trips per table would make
  /// "Run seed" take minutes.
  Future<void> _seedProductionAndConsumptionHistory({
    required int factoryId,
    required int productId,
    required List<Manpower> shifts,
    required List<RawMaterial> materials,
    required List<BomEntry> bom,
    required FinishedStock stock,
  }) async {
    final manpowerCapacity = CapacityService.computeManpowerCapacity(shifts);
    final random = Random(42); // fixed seed: same demo data every time
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: _historyDays - 1));

    final downtimeHoursByDay = <String, double>{
      for (final event in _downtimeEvents)
        _dateKey(now.subtract(Duration(days: event.daysAgo))): event.hours,
    };

    // Replenishment deliveries: (materialName, daysAgo, quantity). Timed and
    // sized so the running stock computed below never needs its safety
    // clamp in practice — see _simulateOrders, which creates matching
    // purchase-order records for these same deliveries.
    const replenishments = [
      ('Plastic Resin', 66, 3500.0),
      ('Plastic Resin', 33, 3500.0),
      ('Colorant', 68, 700.0),
      ('Colorant', 45, 700.0),
      ('Colorant', 18, 700.0),
      ('Packaging Boxes', 58, 2500.0),
      ('Packaging Boxes', 21, 2500.0),
    ];
    final materialByName = {for (final m in materials) m.materialName: m};
    final receiptsByDay = <String, List<(RawMaterial, double)>>{};
    for (final (name, daysAgo, qty) in replenishments) {
      final material = materialByName[name];
      if (material == null) continue;
      receiptsByDay
          .putIfAbsent(_dateKey(now.subtract(Duration(days: daysAgo))), () => [])
          .add((material, qty));
    }

    final materialStock = {for (final m in materials) m.materialId: m.currentStock};
    final movements = <
      ({
        int materialId,
        String movementType,
        double quantity,
        DateTime movementDate,
        String? note,
      })
    >[];

    var stockQty = stock.currentQuantity;
    final stockMovements = <
      ({String movementType, int quantity, DateTime movementDate, String? note})
    >[];

    final days = <
      ({DateTime logDate, int actualOutput, double downtimeHours})
    >[];

    for (var i = 0; i < _historyDays; i++) {
      final day = start.add(Duration(days: i));
      final key = _dateKey(day);

      // Sundays run a skeleton crew; every other day runs close to (and
      // occasionally right at) the manpower-bound ceiling.
      final isSunday = day.weekday == DateTime.sunday;
      final utilisation = isSunday
          ? 0.15 + random.nextDouble() * 0.15
          : 0.82 + random.nextDouble() * 0.16;
      final output = (manpowerCapacity * utilisation).round();

      days.add((
        logDate: day,
        actualOutput: output,
        downtimeHours: downtimeHoursByDay[key] ?? 0,
      ));

      for (final entry in MrpService.computeProductionConsumption(
        bom,
        output,
      ).entries) {
        final available = materialStock[entry.key] ?? 0;
        // Same guard the live automatic-deduction path has: never drive
        // stock negative. Only ever bites if the replenishment schedule
        // above turns out to be too conservative for how a given random
        // seed's daily outputs land.
        final qty = entry.value > available ? available : entry.value;
        if (qty <= 0) continue;
        materialStock[entry.key] = available - qty;
        movements.add((
          materialId: entry.key,
          movementType: RawMaterialMovementType.consumption,
          quantity: qty,
          movementDate: day,
          note: 'Production of $output units',
        ));
      }

      for (final (material, qty)
          in receiptsByDay[key] ?? const <(RawMaterial, double)>[]) {
        materialStock[material.materialId] =
            (materialStock[material.materialId] ?? 0) + qty;
        movements.add((
          materialId: material.materialId,
          movementType: RawMaterialMovementType.receipt,
          quantity: qty,
          movementDate: day,
          note: 'Delivery received',
        ));
      }

      stockQty += output;
      stockMovements.add((
        movementType: StockMovementType.productionIn,
        quantity: output,
        movementDate: day,
        note: null,
      ));
      // A share of *that day's* output, not of the flat demand figure —
      // demand (900/day) is well above the weekend-inclusive daily average
      // output (~600/day, once Sunday's skeleton-crew days are folded in),
      // so shipping close to demand every day would drain stock to zero and
      // pin it there. Shipping a fraction of what actually came off the
      // line instead leaves a modest, realistic buffer that grows slowly —
      // consistent with the demand-exceeds-capacity story told elsewhere in
      // this demo, without the finished-stock screen reading as broken.
      final shipTarget = (output * (0.65 + random.nextDouble() * 0.2)).round();
      final shipped = shipTarget > stockQty ? stockQty : shipTarget;
      if (shipped > 0) {
        stockQty -= shipped;
        stockMovements.add((
          movementType: StockMovementType.shipmentOut,
          quantity: shipped,
          movementDate: day,
          note: 'Retail distribution',
        ));
      }
    }

    await _dailyProductionService.logHistoricalBatch(
      factoryId: factoryId,
      productId: productId,
      days: days,
    );
    await _movementService.recordBulkMovements(
      factoryId: factoryId,
      movements: movements,
      finalStockByMaterialId: materialStock,
    );
    await _stockService.recordBulkMovements(
      stockId: stock.stockId,
      factoryId: factoryId,
      movements: stockMovements,
      finalQuantity: stockQty,
    );
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Purchase-order history: a handful of past cycles per material, already
  /// delivered (their quantities match the receipts folded into the
  /// raw-material ledger in [_seedProductionAndConsumptionHistory] — same
  /// events, two different tables, exactly like a real delivery is both a
  /// PO record and a stock-ledger entry), plus the original three
  /// currently-in-flight orders so the demo still has active/overdue cases
  /// to show.
  Future<void> _simulateOrders(
    int factoryId,
    List<RawMaterial> materials,
    List<Supplier> suppliers,
  ) async {
    RawMaterial materialNamed(String name) =>
        materials.firstWhere((m) => m.materialName == name);
    Supplier supplierFor(int materialId) =>
        suppliers.firstWhere((s) => s.materialId == materialId);

    final now = DateTime.now();
    final colorant = materialNamed('Colorant');
    final resin = materialNamed('Plastic Resin');
    final boxes = materialNamed('Packaging Boxes');

    // (material, quantity, daysAgo the delivery landed, unit price). Must
    // match the `replenishments` list in
    // _seedProductionAndConsumptionHistory so the two tables tell the same
    // story.
    final historical = [
      (resin, 3500.0, 66, 4.6),
      (resin, 3500.0, 33, 4.6),
      (colorant, 700.0, 68, 12.5),
      (colorant, 700.0, 45, 12.5),
      (colorant, 700.0, 18, 12.5),
      (boxes, 2500.0, 58, 0.85),
      (boxes, 2500.0, 21, 0.85),
    ];
    for (final (material, qty, deliveredDaysAgo, price) in historical) {
      final supplier = supplierFor(material.materialId);
      final deliveredAt = now.subtract(Duration(days: deliveredDaysAgo));
      final orderDate = deliveredAt.subtract(
        Duration(days: supplier.leadTimeDays),
      );
      final order = await _orderService.createOrder(
        PurchaseOrder(
          poId: 0,
          supplierId: supplier.supplierId,
          materialId: material.materialId,
          quantity: qty,
          orderDate: orderDate,
          expectedDelivery: deliveredAt,
          status: PurchaseOrderStatus.processing,
          isSimulated: true,
          unitPrice: price,
        ),
        isSimulated: true,
      );
      await _orderService.markDeliveredAt(order, deliveredAt);
    }

    await _orderService.createOrder(
      PurchaseOrder(
        poId: 0,
        supplierId: supplierFor(colorant.materialId).supplierId,
        materialId: colorant.materialId,
        quantity: 1000,
        orderDate: now,
        expectedDelivery: now.add(const Duration(days: 3)),
        status: PurchaseOrderStatus.processing,
        isSimulated: true,
        unitPrice: 12.5,
      ),
      isSimulated: true,
    );

    await _orderService.createOrder(
      PurchaseOrder(
        poId: 0,
        supplierId: supplierFor(resin.materialId).supplierId,
        materialId: resin.materialId,
        quantity: 10000,
        orderDate: now.subtract(const Duration(days: 3)),
        expectedDelivery: now.add(const Duration(days: 2)),
        status: PurchaseOrderStatus.processing,
        isSimulated: true,
        unitPrice: 4.6,
      ),
      isSimulated: true,
    );

    await _orderService.createOrder(
      PurchaseOrder(
        poId: 0,
        supplierId: supplierFor(boxes.materialId).supplierId,
        materialId: boxes.materialId,
        quantity: 5000,
        orderDate: now.subtract(const Duration(days: 8)),
        expectedDelivery: now.subtract(const Duration(days: 3)),
        status: PurchaseOrderStatus.shipped,
        isSimulated: true,
        unitPrice: 0.85,
      ),
      isSimulated: true,
    );
  }
}
