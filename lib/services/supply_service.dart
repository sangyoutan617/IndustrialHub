import '../models/demand_forecast.dart';
import '../models/purchase_order.dart';
import '../models/raw_material.dart';
import '../models/supplier.dart';
import 'capacity_service.dart';
import 'demand_service.dart';
import 'material_service.dart';
import 'mrp_service.dart';
import 'order_service.dart';
import 'supplier_service.dart';

/// Everything a supply screen needs in one shot: raw materials, suppliers,
/// purchase orders, name look-ups, and a computed [MaterialPlan] per
/// material — so screens stop re-querying materials/suppliers/orders
/// independently of each other.
class SupplyOverview {
  final List<RawMaterial> materials;
  final List<Supplier> suppliers;
  final List<PurchaseOrder> orders;
  final List<MaterialPlan> plans;
  final double plannedProductionPerDay;

  /// Whether [plannedProductionPerDay] came from a demand forecast, or is
  /// just an assumption of running at full capacity because no forecast
  /// has been set yet — surfaced in the UI instead of left implicit.
  final bool productionFromForecast;

  const SupplyOverview({
    required this.materials,
    required this.suppliers,
    required this.orders,
    required this.plans,
    required this.plannedProductionPerDay,
    required this.productionFromForecast,
  });

  Map<int, String> get materialNames => {
    for (final m in materials) m.materialId: m.materialName,
  };

  Map<int, String> get supplierNames => {
    for (final s in suppliers) s.supplierId: s.supplierName,
  };

  List<Supplier> suppliersFor(int materialId) =>
      suppliers.where((s) => s.materialId == materialId).toList();

  List<PurchaseOrder> ordersFor(int materialId) =>
      orders.where((o) => o.materialId == materialId).toList();
}

class SupplyService {
  final MaterialService _materialService = MaterialService();
  final SupplierService _supplierService = SupplierService();
  final OrderService _orderService = OrderService();
  final CapacityService _capacityService = CapacityService();
  final DemandService _demandService = DemandService();

  /// Demand-forecast total, capped by what capacity actually allows; falls
  /// back to full capacity when no demand plan has been set yet. Shared by
  /// [load] and the order form, so both agree on the same planned rate.
  static double plannedProductionPerDayFor(
    CapacitySnapshot snapshot,
    List<DemandForecast> forecasts,
  ) {
    final requiredPerDay = forecasts.fold<int>(
      0,
      (sum, f) => sum + f.requiredPerDay,
    );
    if (requiredPerDay > 0) {
      return requiredPerDay.toDouble().clamp(0, snapshot.effectiveCapacity);
    }
    return snapshot.effectiveCapacity;
  }

  Future<SupplyOverview> load(int factoryId) async {
    final materials = await _materialService.getMaterials(factoryId);
    final materialIds = materials.map((m) => m.materialId).toList();

    final results = await Future.wait<dynamic>([
      _supplierService.getSuppliersForMaterials(materialIds),
      _orderService.getOrdersForMaterials(materialIds),
      _capacityService.getSnapshot(factoryId),
      _demandService.getForecasts(factoryId),
    ]);

    final suppliers = results[0] as List<Supplier>;
    final orders = results[1] as List<PurchaseOrder>;
    final snapshot = results[2] as CapacitySnapshot;
    final forecasts = results[3] as List<DemandForecast>;

    final productionFromForecast =
        forecasts.fold<int>(0, (sum, f) => sum + f.requiredPerDay) > 0;
    final plannedProductionPerDay = plannedProductionPerDayFor(
      snapshot,
      forecasts,
    );

    final today = DateTime.now();
    final plans = materials.map((material) {
      final materialSuppliers = suppliers
          .where((s) => s.materialId == material.materialId)
          .toList();
      final materialOrders = orders
          .where((o) => o.materialId == material.materialId)
          .toList();
      return MrpService.buildPlan(
        material: material,
        suppliersForMaterial: materialSuppliers,
        ordersForMaterial: materialOrders,
        plannedProductionPerDay: plannedProductionPerDay,
        today: today,
      );
    }).toList();

    return SupplyOverview(
      materials: materials,
      suppliers: suppliers,
      orders: orders,
      plans: plans,
      plannedProductionPerDay: plannedProductionPerDay,
      productionFromForecast: productionFromForecast,
    );
  }
}
