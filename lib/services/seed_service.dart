import '../models/demand_forecast.dart';
import '../models/factory.dart';
import '../models/machine.dart';
import '../models/manpower.dart';
import '../models/purchase_order.dart';
import '../models/raw_material.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import 'demand_service.dart';
import 'factory_service.dart';
import 'machine_service.dart';
import 'manpower_service.dart';
import 'material_service.dart';
import 'order_service.dart';
import 'stock_service.dart';
import 'supplier_service.dart';

enum SeedOutcome { created, alreadyExists }

class SeedResult {
  final SeedOutcome outcome;
  final Factory factory;

  const SeedResult(this.outcome, this.factory);
}

class SeedService {
  static const _demoFactoryName = 'Demo Beverage Factory';

  final _factoryService = FactoryService();
  final _machineService = MachineService();
  final _manpowerService = ManpowerService();
  final _materialService = MaterialService();
  final _supplierService = SupplierService();
  final _stockService = StockService();
  final _demandService = DemandService();
  final _orderService = OrderService();

  Future<SeedResult> seedDemoData() async {
    final existing = await _factoryService.getFactories();
    for (final factory in existing) {
      if (factory.factoryName == _demoFactoryName) {
        return SeedResult(SeedOutcome.alreadyExists, factory);
      }
    }

    final factory = await _seedFactory();
    await _seedMachines(factory.factoryId);
    await _seedManpower(factory.factoryId);
    final materials = await _seedMaterials(factory.factoryId);
    final suppliers = await _seedSuppliers(materials);
    await _seedStockAndDemand(factory.factoryId);
    await _simulateOrders(materials, suppliers);

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

  Future<List<Machine>> _seedMachines(int factoryId) async {
    final specs = [
      ('Extruder Line A', 50.0, 16.0, 95.0, 'Active'),
      ('Extruder Line B', 40.0, 16.0, 90.0, 'Active'),
      ('Packaging Unit', 100.0, 16.0, 98.0, 'Active'),
      ('Old Mixer', 20.0, 8.0, 80.0, 'Under Maintenance'),
    ];
    final created = <Machine>[];
    for (final (name, rated, hours, uptime, status) in specs) {
      created.add(
        await _machineService.createMachine(
          Machine(
            machineId: 0,
            factoryId: factoryId,
            machineName: name,
            ratedOutputPerHour: rated,
            operatingHoursPerDay: hours,
            uptimePercent: uptime,
            status: status,
            isSimulated: true,
          ),
          isSimulated: true,
        ),
      );
    }
    return created;
  }

  Future<void> _seedManpower(int factoryId) async {
    final specs = [('Day Shift', 15, 8.0, 5.0), ('Night Shift', 8, 8.0, 4.0)];
    for (final (name, workers, hours, perHour) in specs) {
      await _manpowerService.createShift(
        Manpower(
          manpowerId: 0,
          factoryId: factoryId,
          shiftName: name,
          workerCount: workers,
          shiftHours: hours,
          outputPerWorkerHour: perHour,
          isSimulated: true,
        ),
        isSimulated: true,
      );
    }
  }

  Future<List<RawMaterial>> _seedMaterials(int factoryId) async {
    final specs = [
      ('Plastic Resin', 20000.0, 'kg', 3.0, 2000.0),
      ('Colorant', 800.0, 'litres', 0.5, 100.0),
      ('Packaging Boxes', 10000.0, 'boxes', 1.0, 1000.0),
    ];
    final created = <RawMaterial>[];
    for (final (name, stock, unit, consumption, reorder) in specs) {
      created.add(
        await _materialService.createMaterial(
          RawMaterial(
            materialId: 0,
            factoryId: factoryId,
            materialName: name,
            currentStock: stock,
            unit: unit,
            consumptionPerUnit: consumption,
            reorderLevel: reorder,
          ),
        ),
      );
    }
    return created;
  }

  Future<List<Supplier>> _seedSuppliers(List<RawMaterial> materials) async {
    final specs = {
      'Plastic Resin': ('Resin Supply Co', 'Klang', 5, 4.2),
      'Colorant': ('ColorTech Industries', 'Shah Alam', 3, 3.8),
      'Packaging Boxes': ('PackRight Sdn Bhd', 'Klang', 10, 4.7),
    };
    final created = <Supplier>[];
    for (final material in materials) {
      final spec = specs[material.materialName];
      if (spec == null) continue;
      final (name, location, leadTime, rating) = spec;
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
          ),
          isSimulated: true,
        ),
      );
    }
    return created;
  }

  Future<void> _seedStockAndDemand(int factoryId) async {
    const productName = 'Sparkling Water 500ml';
    final stock = await _stockService.createStock(factoryId, productName, 0);

    final now = DateTime.now();
    await _stockService.recordMovement(
      stockId: stock.stockId,
      movementType: StockMovementType.productionIn,
      quantity: 1500,
      movementDate: now.subtract(const Duration(days: 5)),
      note: 'Initial production run',
      isSimulated: true,
    );
    await _stockService.recordMovement(
      stockId: stock.stockId,
      movementType: StockMovementType.shipmentOut,
      quantity: 300,
      movementDate: now.subtract(const Duration(days: 2)),
      note: 'Retail distribution',
      isSimulated: true,
    );

    await _demandService.createForecast(
      DemandForecast(
        demandId: 0,
        factoryId: factoryId,
        productName: productName,
        requiredPerDay: 1000,
      ),
    );
  }

  Future<void> _simulateOrders(
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

    await _orderService.createOrder(
      PurchaseOrder(
        poId: 0,
        supplierId: supplierFor(colorant.materialId).supplierId,
        materialId: colorant.materialId,
        quantity: 1000,
        orderDate: now,
        expectedDelivery: now.add(const Duration(days: 3)),
        status: PurchaseOrderStatus.pending,
        isSimulated: true,
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
      ),
      isSimulated: true,
    );
  }
}
