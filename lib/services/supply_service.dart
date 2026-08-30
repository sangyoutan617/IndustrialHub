import '../models/bom_entry.dart';
import '../models/demand_forecast.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/raw_material.dart';
import '../models/supplier.dart';
import 'bom_service.dart';
import 'capacity_service.dart';
import 'demand_service.dart';
import 'material_service.dart';
import 'mrp_service.dart';
import 'order_service.dart';
import 'product_service.dart';
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

  /// Every product this factory has, and the factory's full bill of
  /// materials across all of them — exposed so a screen can narrate which
  /// products are driving a given material's burn rate (see
  /// material_list_screen.dart's AI prompt) without a separate fetch.
  final List<Product> products;
  final List<BomEntry> bom;

  /// Each product's own planned production for the day — the per-product
  /// figures [plannedProductionPerDay] sums together.
  final Map<int, double> plannedPerProduct;

  /// Sum of every product's own planned production for the day — each
  /// product's demand forecast clamped to that product's own capacity (see
  /// [SupplyService.plannedProductionPerDayFor]), then added together. Not
  /// a single factory-wide rate any more: a factory with several products
  /// has several independent ceilings, and this is their total.
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
    required this.products,
    required this.bom,
    required this.plannedPerProduct,
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

  /// Every product that consumes [materialId], paired with how much of the
  /// material each contributes to its total daily burn rate — sorted
  /// biggest contributor first. Powers the "used by" narration on the
  /// material list's AI prompt.
  List<(Product, double)> productContributionsFor(int materialId) {
    final byId = {for (final p in products) p.productId: p};
    final contributions = <(Product, double)>[
      for (final entry in bom)
        if (entry.materialId == materialId)
          if (byId[entry.productId] != null)
            (
              byId[entry.productId]!,
              (plannedPerProduct[entry.productId] ?? 0) *
                  entry.quantityPerUnit,
            ),
    ].where((c) => c.$2 > 0).toList();
    contributions.sort((a, b) => b.$2.compareTo(a.$2));
    return contributions;
  }
}

class SupplyService {
  final MaterialService _materialService = MaterialService();
  final SupplierService _supplierService = SupplierService();
  final OrderService _orderService = OrderService();
  final CapacityService _capacityService = CapacityService();
  final DemandService _demandService = DemandService();
  final ProductService _productService = ProductService();
  final BomService _bomService = BomService();

  /// Demand-forecast total, capped by what capacity actually allows; falls
  /// back to full capacity when no demand plan has been set yet. Pure — no
  /// DB. Called once per product (see [load]), each with that product's own
  /// [CapacitySnapshot] and the subset of forecasts attributed to it.
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
      _productService.getProducts(factoryId),
      _demandService.getForecasts(factoryId),
      _bomService.getAllForFactory(factoryId),
    ]);

    final suppliers = results[0] as List<Supplier>;
    final orders = results[1] as List<PurchaseOrder>;
    final products = results[2] as List<Product>;
    final allForecasts = results[3] as List<DemandForecast>;
    final bom = results[4] as List<BomEntry>;

    final today = DateTime.now();
    // Only forecasts in effect today drive planned production — an expired
    // or not-yet-started forecast must not inflate demand.
    final forecasts = DemandForecast.activeOn(allForecasts, today);
    final productionFromForecast =
        forecasts.fold<int>(0, (sum, f) => sum + f.requiredPerDay) > 0;

    // Attributes each forecast to its product via the real FK (phase h).
    final forecastsByProduct = <int, List<DemandForecast>>{};
    for (final forecast in forecasts) {
      forecastsByProduct.putIfAbsent(forecast.productId, () => []).add(forecast);
    }

    // Each product's own capacity (its own machines/shifts only — see
    // CapacityService.getSnapshot's productId filter), fetched in parallel.
    final snapshots = await Future.wait(
      products.map(
        (p) => _capacityService.getSnapshot(factoryId, productId: p.productId),
      ),
    );
    final plannedPerProduct = <int, double>{};
    for (var i = 0; i < products.length; i++) {
      plannedPerProduct[products[i].productId] = plannedProductionPerDayFor(
        snapshots[i],
        forecastsByProduct[products[i].productId] ?? const [],
      );
    }
    final plannedProductionPerDay = plannedPerProduct.values.fold<double>(
      0,
      (sum, v) => sum + v,
    );

    final plans = materials.map((material) {
      final materialSuppliers = suppliers
          .where((s) => s.materialId == material.materialId)
          .toList();
      final materialOrders = orders
          .where((o) => o.materialId == material.materialId)
          .toList();
      final burnRate = MrpService.aggregateBurnRate(
        plannedPerProduct: plannedPerProduct,
        bom: bom,
        materialId: material.materialId,
      );
      return MrpService.buildPlan(
        material: material,
        suppliersForMaterial: materialSuppliers,
        ordersForMaterial: materialOrders,
        burnRatePerDay: burnRate,
        today: today,
      );
    }).toList();

    return SupplyOverview(
      materials: materials,
      suppliers: suppliers,
      orders: orders,
      plans: plans,
      products: products,
      bom: bom,
      plannedPerProduct: plannedPerProduct,
      plannedProductionPerDay: plannedProductionPerDay,
      productionFromForecast: productionFromForecast,
    );
  }
}
