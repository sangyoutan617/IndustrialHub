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

class SupplyOverview {
  final List<RawMaterial> materials;
  final List<Supplier> suppliers;
  final List<PurchaseOrder> orders;
  final List<MaterialPlan> plans;

  final List<Product> products;
  final List<BomEntry> bom;

  final Map<int, double> plannedPerProduct;

  final double plannedProductionPerDay;

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
    final forecasts = DemandForecast.activeOn(allForecasts, today);
    final productionFromForecast =
        forecasts.fold<int>(0, (sum, f) => sum + f.requiredPerDay) > 0;

    final forecastsByProduct = <int, List<DemandForecast>>{};
    for (final forecast in forecasts) {
      forecastsByProduct.putIfAbsent(forecast.productId, () => []).add(forecast);
    }

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
