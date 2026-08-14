import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/factory.dart';
import '../../models/raw_material.dart';
import '../../services/bottleneck_service.dart';
import '../../services/material_service.dart';
import '../../services/mrp_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/bottleneck_banner.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
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
  final _materialService = MaterialService();
  final _bottleneckService = BottleneckService();
  final _supplierService = SupplierService();

  _LoadState _state = _LoadState.loading;
  BottleneckResult? _bottleneck;
  List<RawMaterial> _lowStockMaterials = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final bottleneck = await _bottleneckService.computeForFactory(
        widget.factory.factoryId,
      );
      final materials = await _materialService.getMaterials(
        widget.factory.factoryId,
      );
      final lowStock = materials
          .where((m) => m.currentStock < m.reorderLevel)
          .toList();

      setState(() {
        _bottleneck = bottleneck;
        _lowStockMaterials = lowStock;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _raisePurchaseOrder(RawMaterial material) async {
    final suppliers = await _supplierService.getSuppliersForMaterials([
      material.materialId,
    ]);
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
            quantity: material.reorderLevel - material.currentStock,
          ),
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.factory.factoryName)),
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
    final bottleneck = _bottleneck!;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
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
          ),
          BottleneckBanner(factoryId: factory.factoryId),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alerts', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (bottleneck.hasData && !bottleneck.canMeetDemand)
                  _alertTile(
                    icon: Icons.warning_amber_rounded,
                    title:
                        'Output shortfall: short by ${bottleneck.shortfall!.toStringAsFixed(0)} units/day',
                    subtitle:
                        'Limiting resource: ${_resourceLabel(bottleneck.limiter ?? bottleneck.bottleneckResource)}',
                  ),
                for (final material in _lowStockMaterials)
                  _alertTile(
                    icon: Icons.inventory_2_outlined,
                    title:
                        '${material.materialName}: ${material.currentStock.toStringAsFixed(0)} ${material.unit} in stock',
                    subtitle:
                        'Reorder level: ${material.reorderLevel.toStringAsFixed(0)} ${material.unit}',
                    trailing: TextButton(
                      onPressed: () => _raisePurchaseOrder(material),
                      child: const Text('Raise PO'),
                    ),
                  ),
                if ((!bottleneck.hasData || bottleneck.canMeetDemand) &&
                    _lowStockMaterials.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No open alerts for this factory.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
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

  Widget _alertTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryDark),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }
}
