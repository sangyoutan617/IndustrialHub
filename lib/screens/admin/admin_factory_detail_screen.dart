import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../models/factory.dart';
import '../../models/product.dart';
import '../../models/supplier.dart';
import '../../services/bottleneck_service.dart';
import '../../services/mrp_service.dart';
import '../../services/product_service.dart';
import '../../services/supplier_service.dart';
import '../../services/supply_service.dart';
import '../../widgets/bottleneck_banner.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import '../supply/order_form_screen.dart';

/// Read-only admin drill-in for a single factory. Alerts here are computed
/// live from current_stock / reorder_level and the bottleneck engine — there
/// is no alerts table to mark rows resolved. Raising a purchase order is the
/// only action offered, and it goes through Module 3's normal create-order
/// flow rather than mutating stock from this screen.
class AdminFactoryDetailScreen extends StatefulWidget {
  final Factory factory;

  const AdminFactoryDetailScreen({super.key, required this.factory});

  @override
  State<AdminFactoryDetailScreen> createState() =>
      _AdminFactoryDetailScreenState();
}

enum _LoadState { loading, error, ready }

class _AdminFactoryDetailScreenState extends State<AdminFactoryDetailScreen> {
  final _supplyService = SupplyService();
  final _bottleneckService = BottleneckService();
  final _supplierService = SupplierService();
  final _productService = ProductService();

  _LoadState _state = _LoadState.loading;
  List<ProductBottleneck> _productBottlenecks = [];
  List<MaterialPlan> _lowStockPlans = [];
  List<Product> _products = [];
  int? _selectedProductId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Product _defaultProduct(List<Product> products) =>
      products.firstWhere((p) => !p.isGeneral, orElse: () => products.first);

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final products = await _productService.getProducts(
        widget.factory.factoryId,
      );
      if (products.isEmpty) {
        // Shouldn't happen — every factory gets an auto-created General
        // product — but there's nothing meaningful to show a bottleneck
        // verdict for if it somehow does.
        setState(() => _state = _LoadState.error);
        return;
      }
      final selected = _selectedProductId != null
          ? products.firstWhere(
              (p) => p.productId == _selectedProductId,
              orElse: () => _defaultProduct(products),
            )
          : _defaultProduct(products);

      // Every product's own verdict, not just the picked one — the alerts
      // section below lists every shortfall across the whole factory. The
      // product picker + BottleneckBanner underneath is for drilling into
      // one product's full detail, a separate concern.
      final bottlenecks = await Future.wait(
        products.map(
          (p) => _bottleneckService.computeForProduct(
            widget.factory.factoryId,
            p.productId,
          ),
        ),
      );
      final productBottlenecks = [
        for (var i = 0; i < products.length; i++)
          ProductBottleneck(product: products[i], bottleneck: bottlenecks[i]),
      ];

      final overview = await _supplyService.load(widget.factory.factoryId);
      final lowStock = overview.plans
          .where((p) => p.belowReorderLevel)
          .toList();

      setState(() {
        _products = products;
        _selectedProductId = selected.productId;
        _productBottlenecks = productBottlenecks;
        _lowStockPlans = lowStock;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  void _setProduct(int? productId) {
    if (productId == null || productId == _selectedProductId) return;
    setState(() => _selectedProductId = productId);
    _load();
  }

  Future<void> _raisePurchaseOrder(MaterialPlan plan) async {
    final material = plan.material;
    List<Supplier> suppliers;
    try {
      suppliers = await _supplierService.getSuppliersForMaterials([
        material.materialId,
      ]);
    } catch (e) {
      // Unguarded, a failed fetch here made the "Raise PO" tap do nothing
      // (and threw in the background) — tell the admin instead.
      debugPrint('admin: failed to load suppliers for material: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load suppliers. Please try again.'),
        ),
      );
      return;
    }
    final supplier = MrpService.bestSupplier(suppliers);
    if (supplier == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No supplier assigned to ${material.materialName} yet — add one first.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderFormScreen(
          factoryId: widget.factory.factoryId,
          prefill: OrderFormPrefill(
            materialId: material.materialId,
            supplierId: supplier.supplierId,
            quantity: plan.reorderLevel - material.currentStock,
          ),
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.factory.factoryName,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final factory = widget.factory;
    final shortProducts = _productBottlenecks
        .where((p) => p.bottleneck.hasData && !p.bottleneck.canMeetDemand)
        .toList();

    final infoCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              factory.factoryName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (factory.location != null) factory.location!,
                if (factory.state != null) factory.state!,
              ].join(', '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (factory.msicCode != null) ...[
              const SizedBox(height: 4),
              Text(
                'MSIC ${factory.msicCode}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
    
    final productPicker = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonFormField<int>(
        initialValue: _selectedProductId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Product'),
        items: [
          for (final product in _products)
            DropdownMenuItem(
              value: product.productId,
              child: Text(
                product.isGeneral
                    ? '${product.productName} (auto-created)'
                    : product.productName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _setProduct,
      ),
    );

    final bottleneckBanner = BottleneckBanner(
      factoryId: factory.factoryId,
      productId: _selectedProductId!,
    );

    final alertsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Alerts', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final pb in shortProducts) ...[
          InfoBanner(
            status: AppStatus.danger,
            title:
                '${pb.product.productName}: short by '
                '${formatWhole(pb.bottleneck.shortfall!)} units/day',
            message:
                'Limiting resource: ${_resourceLabel(pb.bottleneck.limiter ?? pb.bottleneck.bottleneckResource)}',
          ),
          const SizedBox(height: 8),
        ],
        for (final plan in _lowStockPlans) ...[
          InfoBanner(
            status: AppStatus.danger,
            title:
                '${plan.material.materialName}: ${formatWhole(plan.material.currentStock)} ${plan.material.unit} in stock',
            message:
                'Reorder level: ${formatWhole(plan.reorderLevel)} ${plan.material.unit}',
            actionLabel: 'Raise PO',
            onAction: () => _raisePurchaseOrder(plan),
          ),
          const SizedBox(height: 8),
        ],
        if (shortProducts.isEmpty && _lowStockPlans.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No open alerts for this factory.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          infoCard,
          const SizedBox(height: 8),
          productPicker,
          bottleneckBanner,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: alertsSection,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _resourceLabel(String resource) {
    switch (resource) {
      case 'MACHINE':
        return 'Machine';
      case 'MANPOWER':
        return 'Manpower';
      case 'RAW MATERIAL':
        return 'Raw material';
      default:
        return resource;
    }
  }

}
