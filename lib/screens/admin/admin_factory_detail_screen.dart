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
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/bottleneck_banner.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import '../supply/order_form_screen.dart';

class AdminFactoryDetailScreen extends StatefulWidget {
  final Factory factory;

  const AdminFactoryDetailScreen({super.key, required this.factory});

  @override
  State<AdminFactoryDetailScreen> createState() =>
      _AdminFactoryDetailScreenState();
}

enum _LoadState { loading, error, ready }

const _allProductsId = -1;

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
        setState(() => _state = _LoadState.error);
        return;
      }
      final isAll = _selectedProductId == _allProductsId;
      final selected = isAll
          ? null
          : _selectedProductId != null
          ? products.firstWhere(
              (p) => p.productId == _selectedProductId,
              orElse: () => _defaultProduct(products),
            )
          : _defaultProduct(products);

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
        _selectedProductId = isAll ? _allProductsId : selected!.productId;
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
  }

  Future<void> _raisePurchaseOrder(MaterialPlan plan) async {
    final material = plan.material;
    List<Supplier> suppliers;
    try {
      suppliers = await _supplierService.getSuppliersForMaterials([
        material.materialId,
      ]);
    } catch (e) {
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
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(widget.factory.factoryName),
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

    final address = [
      if (factory.location != null) factory.location!,
      if (factory.state != null) factory.state!,
    ].join(', ');

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
            if (address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(address, style: Theme.of(context).textTheme.bodySmall),
            ],
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
      child: AppDropdownField<int>(
        idPrefix: 'product',
        label: 'Product',
        required: false,
        value: _selectedProductId,
        entries: [
          const DropdownMenuEntry(
            value: _allProductsId,
            label: 'All products',
          ),
          for (final product in _products)
            DropdownMenuEntry(
              value: product.productId,
              label: product.isGeneral
                  ? '${product.productName} (auto-created)'
                  : product.productName,
            ),
        ],
        onChanged: _setProduct,
      ),
    );

    final isAll = _selectedProductId == _allProductsId;
    final healthOrBanner = KeyedSubtree(
      key: ValueKey(isAll),
      child: isAll
          ? _buildFactoryHealth()
          : BottleneckBanner(
              factoryId: factory.factoryId,
              productId: _selectedProductId!,
            ),
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
          healthOrBanner,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: alertsSection,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFactoryHealth() {
    final scheme = Theme.of(context).colorScheme;
    final withDemand = _productBottlenecks
        .where((p) => p.bottleneck.hasData && p.bottleneck.requiredPerDay > 0)
        .toList();
    final meeting = withDemand.where((p) => p.bottleneck.canMeetDemand).length;
    final allMet = withDemand.isNotEmpty && meeting == withDemand.length;
    var totalAchievable = 0.0;
    var totalDemand = 0.0;
    for (final p in withDemand) {
      totalAchievable += p.bottleneck.achievable;
      totalDemand += p.bottleneck.requiredPerDay;
    }
    final shortfall = totalDemand - totalAchievable;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Factory health',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (withDemand.isNotEmpty)
                    StatusChip(
                      label: allMet ? 'On track' : 'Bottleneck',
                      status: allMet ? AppStatus.success : AppStatus.warning,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Products meeting demand',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      withDemand.isEmpty
                          ? '—'
                          : '$meeting / ${withDemand.length}',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      withDemand.isEmpty
                          ? 'No product has a demand target and capacity data yet.'
                          : allMet
                          ? 'Total output ${formatWhole(totalAchievable)} · demand ${formatWhole(totalDemand)}'
                          : 'Total output ${formatWhole(totalAchievable)} · demand ${formatWhole(totalDemand)} · short by ${formatWhole(shortfall)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final pb in _productBottlenecks) ...[
                _healthRow(pb),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _healthRow(ProductBottleneck pb) {
    final b = pb.bottleneck;
    final AppStatus status;
    final String detail;
    if (!b.hasData) {
      status = AppStatus.neutral;
      detail = 'No capacity data';
    } else if (b.requiredPerDay <= 0) {
      status = AppStatus.neutral;
      detail = 'No demand target';
    } else if (b.canMeetDemand) {
      status = AppStatus.success;
      detail = 'Meets demand';
    } else {
      status = AppStatus.danger;
      detail =
          'Short ${formatWhole(b.shortfall!)}/day · '
          '${_resourceLabel(b.limiter ?? b.bottleneckResource)}';
    }
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: status.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            pb.product.productName,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
      ],
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
